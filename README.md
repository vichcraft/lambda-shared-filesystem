# Lambda + EFS Proof-of-Concept

A proof-of-concept implementation demonstrating an innovative serverless architecture that combines AWS Lambda with Amazon EFS. This system showcases how multiple ephemeral Lambda functions can share state through a common mounted filesystem, creating a distributed serverless system with persistent shared storage.

## Overview

This POC implements a machine learning inference pipeline where:
- A **Producer Lambda** ingests models from S3 and writes them to EFS
- A **Consumer Lambda** performs inference by loading models from the shared EFS filesystem
- Both functions communicate through a shared EFS mount point at `/mnt/efs`
- S3 serves as the system of record; EFS provides the shared working set

### Key Features

- **Serverless Architecture**: No servers to manage, automatic scaling
- **Shared State**: Multiple Lambda functions access the same filesystem
- **Event-Driven**: S3 ObjectCreated events automatically trigger ingestion
- **RESTful API**: Simple HTTP endpoints for testing and integration
- **Infrastructure as Code**: Fully reproducible deployment using Terraform
- **Cost-Effective**: ~$4-5/month for POC usage

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Cloud                               │
│                                                                   │
│  ┌────────────┐                                                  │
│  │  S3 Bucket │                                                  │
│  │            │                                                  │
│  │ models/    │──────┐                                          │
│  │ inputs/    │      │ ObjectCreated Event                      │
│  │ outputs/   │      │                                          │
│  └────────────┘      │                                          │
│         │             │                                          │
│         │ Upload      │                                          │
│         │             ▼                                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                        VPC                                │  │
│  │                                                            │  │
│  │  ┌──────────────┐         ┌──────────────┐               │  │
│  │  │  Producer    │         │  Consumer    │               │  │
│  │  │  Lambda      │         │  Lambda      │               │  │
│  │  │  (App1)      │         │  (App2)      │               │  │
│  │  └──────┬───────┘         └──────┬───────┘               │  │
│  │         │                         │                        │  │
│  │         └─────────┬───────────────┘                        │  │
│  │                   │ Mount /mnt/efs                         │  │
│  │            ┌──────▼──────────┐                             │  │
│  │            │   EFS File      │                             │  │
│  │            │   System        │                             │  │
│  │            │                 │                             │  │
│  │            │  /models/       │                             │  │
│  │            │  /inputs/       │                             │  │
│  │            │  /outputs/      │                             │  │
│  │            └─────────────────┘                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌────────────────┐                                             │
│  │  API Gateway   │                                             │
│  │                │                                             │
│  │  POST /ingest  │──────Trigger Producer                      │
│  │  POST /predict │──────Trigger Consumer                      │
│  └────────────────┘                                             │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before deploying this POC, ensure you have:

### Required Tools

- **AWS CLI** (v2.x or higher)
  - Installation: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
  - Configured with credentials: `aws configure`
  
- **Terraform** (v1.5.0 or higher)
  - Installation: https://developer.hashicorp.com/terraform/downloads
  - Verify: `terraform --version`
  
- **Python** (3.11 or higher)
  - Installation: https://www.python.org/downloads/
  - Verify: `python3 --version`

### AWS Account Requirements

- Active AWS account with appropriate permissions
- IAM permissions to create:
  - VPC, subnets, security groups, VPC endpoints
  - EFS file systems, mount targets, access points
  - S3 buckets and event notifications
  - Lambda functions and IAM roles
  - API Gateway REST APIs
  - CloudWatch log groups

### Recommended IAM Permissions

For deployment, your AWS user/role should have:
- `AdministratorAccess` (simplest for POC)
- Or specific permissions: `VPCFullAccess`, `AmazonElasticFileSystemFullAccess`, `AWSLambda_FullAccess`, `AmazonS3FullAccess`, `AmazonAPIGatewayAdministrator`, `IAMFullAccess`

## Deployment Guide

### Step 1: Clone or Download the Repository

```bash
# If using git
git clone <repository-url>
cd lambda-efs-poc

# Or download and extract the ZIP file
```

### Step 2: Configure Terraform Variables

```bash
cd terraform

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the file with your preferred values
nano terraform.tfvars  # or use your preferred editor
```

**Example `terraform.tfvars`:**

```hcl
region      = "us-east-1"
prefix      = "lambda-efs-poc"
environment = "dev"
```

**Configuration Options:**

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `region` | AWS region for deployment | `us-east-1` | No |
| `prefix` | Prefix for resource naming | `lambda-efs-poc` | No |
| `environment` | Environment name (dev/test/prod) | `dev` | No |

### Step 3: Initialize Terraform

```bash
terraform init
```

This command:
- Downloads required Terraform providers (AWS, Archive)
- Initializes the backend
- Prepares modules for use

**Expected output:**
```
Initializing modules...
Initializing the backend...
Initializing provider plugins...
Terraform has been successfully initialized!
```

### Step 4: Review the Deployment Plan

```bash
terraform plan -out=tfplan
```

This command:
- Shows all resources that will be created
- Validates your configuration
- Saves the plan to a file for the next step

**Review the output carefully** to ensure:
- Resources are being created in the correct region
- Naming conventions match your expectations
- No unexpected resources are being created

### Step 5: Deploy the Infrastructure

```bash
terraform apply tfplan
```

This command:
- Creates all AWS resources defined in the plan
- Takes approximately 3-5 minutes to complete
- Displays progress as resources are created

**Expected output:**
```
Apply complete! Resources: 35 added, 0 changed, 0 destroyed.

Outputs:

api_gateway_url = "https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod"
consumer_lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:lambda-efs-poc-dev-consumer"
efs_access_point_arn = "arn:aws:elasticfilesystem:us-east-1:123456789012:access-point/fsap-..."
efs_file_system_id = "fs-0123456789abcdef"
producer_lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:lambda-efs-poc-dev-producer"
s3_bucket_name = "lambda-efs-poc-dev-ml-models-123456789012"
...
```

### Step 6: Capture Deployment Outputs

```bash
terraform output -json > outputs.json
```

This creates a JSON file with all deployment information needed for testing.

### Step 7: Verify Deployment

Check that key resources were created:

```bash
# Verify EFS file system
aws efs describe-file-systems --query "FileSystems[?Name=='lambda-efs-poc-dev-efs']"

# Verify Lambda functions
aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'lambda-efs-poc')]"

# Verify S3 bucket
aws s3 ls | grep lambda-efs-poc

# Verify API Gateway
aws apigateway get-rest-apis --query "items[?name=='lambda-efs-poc-dev-api']"
```

## API Usage

The deployed system exposes two REST API endpoints through API Gateway.

### Base URL

After deployment, get your API Gateway URL:

```bash
cd terraform
terraform output api_gateway_url
```

Example: `https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod`

### Endpoint 1: POST /ingest

Ingests data and writes it to EFS.

**Purpose**: Upload or reference data to be stored on the shared EFS filesystem.

**Request Format:**

```bash
# Option 1: Provide raw data
curl -X POST https://YOUR_API_URL/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "data": "sample model data or base64 encoded content",
    "filename": "model.pt"
  }'

# Option 2: Reference an S3 key
curl -X POST https://YOUR_API_URL/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "key": "models/resnet50.pt"
  }'
```

**Success Response (200 OK):**

```json
{
  "fileId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "efsPath": "/mnt/efs/models/model.pt",
  "s3Key": "models/model.pt",
  "sizeBytes": 12345,
  "status": "created"
}
```

**Response Fields:**
- `fileId`: Unique identifier for the file (use this for /predict)
- `efsPath`: Path where file is stored on EFS
- `s3Key`: Original S3 key (if applicable)
- `sizeBytes`: File size in bytes
- `status`: `created` or `exists` (if file already present)

**Error Responses:**

```json
// 400 Bad Request - Invalid input
{
  "error": "INVALID_REQUEST",
  "message": "Request body must contain 'key' or 'data' field"
}

// 404 Not Found - S3 object doesn't exist
{
  "error": "S3_NOT_FOUND",
  "key": "models/nonexistent.pt",
  "message": "S3 object not found"
}

// 413 Payload Too Large - File exceeds 1GB
{
  "error": "FILE_TOO_LARGE",
  "maxSize": "1GB",
  "message": "File size exceeds maximum allowed"
}

// 500 Internal Server Error - EFS or processing failure
{
  "error": "EFS_WRITE_FAILED",
  "stage": "write",
  "requestId": "abc-123-def",
  "message": "Failed to write file to EFS"
}
```

### Endpoint 2: POST /predict

Processes data by reading from EFS.

**Purpose**: Perform inference or processing on data stored in the shared EFS filesystem.

**Request Format:**

```bash
curl -X POST https://YOUR_API_URL/predict \
  -H "Content-Type: application/json" \
  -d '{
    "fileId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "model": "model.pt"
  }'
```

**Request Fields:**
- `fileId`: The file identifier returned from /ingest
- `model`: The model filename to load from EFS

**Success Response (200 OK):**

```json
{
  "fileId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "efsPath": "/mnt/efs/outputs/a1b2c3d4-e5f6-7890-abcd-ef1234567890.result",
  "s3Key": "outputs/a1b2c3d4-e5f6-7890-abcd-ef1234567890.result",
  "durationMs": 234,
  "result": {
    "modelSize": 12345,
    "checksum": "abc123...",
    "processed": true
  }
}
```

**Response Fields:**
- `fileId`: Request file identifier
- `efsPath`: Path where result is stored on EFS
- `s3Key`: S3 path where result is archived (if enabled)
- `durationMs`: Processing duration in milliseconds
- `result`: Processing output (structure varies by implementation)

**Error Responses:**

```json
// 404 Not Found - Model file doesn't exist on EFS
{
  "error": "NOT_FOUND",
  "fileId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "message": "Model file not found on EFS"
}

// 400 Bad Request - Invalid input
{
  "error": "INVALID_REQUEST",
  "message": "Request body must contain 'fileId' and 'model' fields"
}

// 500 Internal Server Error - Processing failure
{
  "error": "PROCESSING_FAILED",
  "requestId": "abc-123-def",
  "message": "Failed to process inference"
}
```

### Complete Example Workflow

```bash
# Set your API URL
API_URL="https://YOUR_API_URL"

# Step 1: Ingest data
RESPONSE=$(curl -s -X POST $API_URL/ingest \
  -H "Content-Type: application/json" \
  -d '{"data": "sample model data", "filename": "test-model.pt"}')

echo "Ingest response: $RESPONSE"

# Step 2: Extract fileId from response
FILE_ID=$(echo $RESPONSE | jq -r '.fileId')
echo "File ID: $FILE_ID"

# Step 3: Run prediction
curl -X POST $API_URL/predict \
  -H "Content-Type: application/json" \
  -d "{\"fileId\": \"$FILE_ID\", \"model\": \"test-model.pt\"}"
```

### Alternative: S3 Event Trigger

Instead of using the /ingest API, you can upload files directly to S3:

```bash
# Get your S3 bucket name
BUCKET=$(cd terraform && terraform output -raw s3_bucket_name)

# Upload a model file
aws s3 cp my-model.pt s3://$BUCKET/models/my-model.pt

# This automatically triggers the Producer Lambda
# Wait a few seconds, then use /predict with the model name
curl -X POST $API_URL/predict \
  -H "Content-Type: application/json" \
  -d '{"fileId": "my-model", "model": "my-model.pt"}'
```

### Testing with the Demonstration Script

For comprehensive testing, use the included demonstration script:

```bash
# Install dependencies
pip install -r requirements.txt

# Run all tests
python demonstration.py --config terraform/outputs.json
```

See `DEMONSTRATION_README.md` for complete documentation.

## Cleanup Procedure

When you're done with the POC, follow these steps to remove all resources and avoid ongoing charges.

### Step 1: Empty the S3 Bucket

Terraform cannot delete non-empty S3 buckets, so you must empty it first:

```bash
# Get your bucket name
cd terraform
BUCKET=$(terraform output -raw s3_bucket_name)

# Remove all objects
aws s3 rm s3://$BUCKET --recursive

# Verify bucket is empty
aws s3 ls s3://$BUCKET
```

### Step 2: Destroy Infrastructure

```bash
# Still in the terraform/ directory
terraform destroy
```

**You will be prompted to confirm.** Type `yes` to proceed.

**Expected output:**
```
Plan: 0 to add, 0 to change, 35 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

...

Destroy complete! Resources: 35 destroyed.
```

### Step 3: Verify Cleanup

Check that resources were deleted:

```bash
# Check EFS file systems
aws efs describe-file-systems --query "FileSystems[?Name=='lambda-efs-poc-dev-efs']"

# Check Lambda functions
aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'lambda-efs-poc')]"

# Check S3 bucket
aws s3 ls | grep lambda-efs-poc
```

All commands should return empty results.

### Step 4: Manual Cleanup (If Needed)

Some resources may require manual cleanup:

#### CloudWatch Log Groups

Lambda functions create log groups that persist after deletion:

```bash
# List log groups
aws logs describe-log-groups --query "logGroups[?contains(logGroupName, 'lambda-efs-poc')]"

# Delete log groups
aws logs delete-log-group --log-group-name /aws/lambda/lambda-efs-poc-dev-producer
aws logs delete-log-group --log-group-name /aws/lambda/lambda-efs-poc-dev-consumer
```

#### ENIs (Elastic Network Interfaces)

Lambda functions in VPCs create ENIs that may take a few minutes to delete automatically. If you encounter errors during `terraform destroy`, wait 5-10 minutes and try again.

#### EFS Mount Targets

If EFS mount targets fail to delete, they may still be in use:

```bash
# Wait a few minutes for Lambda ENIs to fully detach
# Then retry destroy
terraform destroy
```

### Cleanup Verification Checklist

- [ ] S3 bucket deleted
- [ ] EFS file system deleted
- [ ] Lambda functions deleted
- [ ] API Gateway deleted
- [ ] VPC and subnets deleted
- [ ] Security groups deleted
- [ ] IAM roles deleted
- [ ] CloudWatch log groups deleted (manual)

## Cost Estimation and AWS Free Tier

### Estimated Monthly Costs

Based on typical POC usage (1000 Producer invocations, 5000 Consumer invocations per month):

| Service | Usage | Unit Cost | Monthly Cost | Free Tier |
|---------|-------|-----------|--------------|-----------|
| **Lambda (Producer)** | 1000 invocations × 2s × 1024MB | $0.0000166667/GB-second | $0.03 | 1M requests + 400K GB-seconds/month |
| **Lambda (Consumer)** | 5000 invocations × 2s × 2048MB | $0.0000166667/GB-second | $0.33 | Covered by free tier |
| **Lambda Requests** | 6000 requests | $0.20/1M requests | $0.00 | Covered by free tier |
| **EFS Storage** | 10 GB | $0.30/GB-month | **$3.00** | No free tier |
| **EFS Requests** | ~6000 requests | Included in storage | $0.00 | N/A |
| **S3 Storage** | 20 GB | $0.023/GB-month | $0.46 | 5 GB free |
| **S3 Requests** | ~6000 PUT/GET | $0.005/1000 PUT, $0.0004/1000 GET | $0.03 | 20K GET, 2K PUT free |
| **API Gateway** | 6000 requests | $3.50/1M requests | $0.02 | 1M requests/month (first 12 months) |
| **CloudWatch Logs** | 1 GB | $0.50/GB | $0.50 | 5 GB ingestion free |
| **VPC (S3 Endpoint)** | 1 endpoint | Free | $0.00 | Always free |
| **Data Transfer** | Minimal (same region) | $0.00 | $0.00 | N/A |
| | | **Total** | **~$4.37/month** | |

### With AWS Free Tier (First 12 Months)

If you're within the AWS Free Tier period:

- Lambda: Fully covered (under 1M requests and 400K GB-seconds)
- S3: Partially covered (5 GB storage, 20K GET, 2K PUT)
- API Gateway: Fully covered (under 1M requests)
- CloudWatch: Partially covered (5 GB ingestion)
- **EFS: Not covered** (no free tier for EFS)

**Estimated cost with free tier: ~$3.50/month** (primarily EFS storage)

### Cost Breakdown by Component

**Most Expensive:**
1. **EFS Storage** (~$3.00/month) - 68% of total cost
2. **S3 Storage** (~$0.46/month) - 11% of total cost
3. **CloudWatch Logs** (~$0.50/month) - 11% of total cost
4. **Lambda Compute** (~$0.36/month) - 8% of total cost

### Cost Optimization Tips

#### 1. Reduce EFS Storage Costs

```bash
# Use EFS Infrequent Access (IA) storage class for older files
# Automatically moves files not accessed for 30 days to IA (85% cheaper)
# Enable via Lifecycle Policy in EFS console or Terraform
```

**Savings**: Up to $2.55/month (85% reduction on IA files)

#### 2. Clean Up Old Files

```bash
# Regularly delete old models and outputs from EFS
aws efs describe-file-systems --file-system-id fs-xxx
# Then manually delete files or create a cleanup Lambda
```

**Savings**: Proportional to storage reduction

#### 3. Use S3 Intelligent-Tiering

```bash
# Enable Intelligent-Tiering for S3 bucket
# Automatically moves infrequently accessed objects to cheaper tiers
```

**Savings**: Up to 68% on infrequently accessed S3 objects

#### 4. Reduce Lambda Memory

If your workload allows, reduce Lambda memory allocation:

```hcl
# In terraform/modules/lambda/main.tf
memory_size = 512  # Instead of 1024 for Producer
memory_size = 1024 # Instead of 2048 for Consumer
```

**Savings**: Up to 50% on Lambda compute costs

#### 5. Reduce CloudWatch Log Retention

```bash
# Set shorter retention period (default is 7 days in this POC)
aws logs put-retention-policy \
  --log-group-name /aws/lambda/lambda-efs-poc-dev-producer \
  --retention-in-days 1
```

**Savings**: Minimal (logs are cheap), but reduces clutter

#### 6. Delete Resources When Not in Use

For a POC that's not actively used:

```bash
# Destroy infrastructure when not testing
terraform destroy

# Redeploy when needed
terraform apply
```

**Savings**: 100% (no charges when resources don't exist)

### Cost Monitoring

Set up billing alerts to avoid surprises:

```bash
# Enable billing alerts in AWS Console
# Set threshold at $5-10/month for this POC
# Receive email when threshold is exceeded
```

**Steps:**
1. Go to AWS Billing Console
2. Navigate to "Billing Preferences"
3. Enable "Receive Billing Alerts"
4. Create CloudWatch alarm for billing threshold

### Cost Comparison: Alternative Architectures

| Architecture | Monthly Cost | Tradeoffs |
|--------------|--------------|-----------|
| **Lambda + EFS** (this POC) | $4.37 | Shared state, low latency, moderate cost |
| **Lambda + S3 only** | $1.00 | No shared state, higher latency, lowest cost |
| **Lambda + EFS + NAT Gateway** | $36.00 | Internet access, much higher cost |
| **EC2 + EFS** | $15.00 | Always-on, manual scaling, more ops overhead |
| **ECS Fargate + EFS** | $25.00 | Container-based, more complex, higher cost |

### Free Tier Expiration

After 12 months, AWS Free Tier expires for:
- Lambda (1M requests/month becomes paid)
- API Gateway (1M requests/month becomes paid)
- S3 (5 GB storage becomes paid)

**Estimated cost after free tier expiration: ~$5-6/month** (assuming same usage)

### Actual Cost Tracking

To see your actual costs:

```bash
# View current month's costs
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=SERVICE
```

Or use the AWS Cost Explorer in the console for detailed breakdowns.

## Project Structure

```
lambda-efs-poc/
├── README.md                           # This file
├── DEMONSTRATION_README.md             # Demonstration script documentation
├── QUICK_START.md                      # Quick start guide
├── demonstration.py                    # Test and validation script
├── requirements.txt                    # Python dependencies
├── .kiro/
│   └── specs/
│       └── lambda-efs-poc/
│           ├── requirements.md         # Feature requirements
│           ├── design.md               # Architecture design
│           └── tasks.md                # Implementation tasks
└── terraform/
    ├── main.tf                         # Root Terraform configuration
    ├── variables.tf                    # Input variables
    ├── outputs.tf                      # Deployment outputs
    ├── terraform.tfvars.example        # Example configuration
    ├── README.md                       # Terraform-specific docs
    ├── modules/
    │   ├── vpc/                        # VPC infrastructure
    │   ├── efs/                        # EFS file system
    │   ├── s3/                         # S3 bucket
    │   └── lambda/                     # Lambda functions & API Gateway
    └── lambda_code/
        ├── producer/                   # Producer Lambda code
        │   └── lambda_function.py
        └── consumer/                   # Consumer Lambda code
            └── lambda_function.py
```

## Troubleshooting

### Deployment Issues

#### Error: "Error creating VPC"
- **Cause**: Insufficient IAM permissions or VPC limit reached
- **Solution**: Check IAM permissions, verify VPC limit in AWS Console

#### Error: "Error creating EFS mount target"
- **Cause**: Subnet or security group not ready
- **Solution**: Wait a few seconds and retry `terraform apply`

#### Error: "Error creating Lambda function"
- **Cause**: IAM role not ready or code package too large
- **Solution**: Verify IAM role exists, check Lambda code size

### Runtime Issues

#### API returns 500 error
- **Cause**: Lambda function error (EFS mount failure, code bug)
- **Solution**: Check CloudWatch logs for the Lambda function

```bash
aws logs tail /aws/lambda/lambda-efs-poc-dev-producer --follow
```

#### Consumer returns 404 (file not found)
- **Cause**: Model file not yet written to EFS
- **Solution**: Ensure Producer was invoked first, check EFS contents

#### Slow Lambda performance
- **Cause**: Cold start (first invocation after deployment)
- **Solution**: This is expected; subsequent invocations will be faster

### Cleanup Issues

#### Error: "Error deleting S3 bucket"
- **Cause**: Bucket not empty
- **Solution**: Empty bucket first: `aws s3 rm s3://BUCKET --recursive`

#### Error: "Error deleting EFS mount target"
- **Cause**: Lambda ENIs still attached
- **Solution**: Wait 5-10 minutes for ENIs to detach, then retry

## Next Steps

After successful deployment:

1. **Run the demonstration script** to validate the system:
   ```bash
   python demonstration.py --config terraform/outputs.json
   ```

2. **Review the results** in `demonstration_results.json` and `demonstration_summary.txt`

3. **Explore CloudWatch logs** to see Lambda execution details

4. **Experiment with the API** using curl or Postman

5. **Collect evidence** for your academic paper:
   - Take screenshots of EFS Access Point configuration
   - Take screenshots of Lambda EFS mount configuration
   - Export CloudWatch logs
   - Include performance metrics from demonstration script

6. **Review the design document** (`.kiro/specs/lambda-efs-poc/design.md`) for architecture details

## Support and Documentation

- **Requirements**: `.kiro/specs/lambda-efs-poc/requirements.md`
- **Design**: `.kiro/specs/lambda-efs-poc/design.md`
- **Tasks**: `.kiro/specs/lambda-efs-poc/tasks.md`
- **Demonstration**: `DEMONSTRATION_README.md`
- **Terraform**: `terraform/README.md`

## License

This is a proof-of-concept implementation for academic purposes.

## Acknowledgments

This POC demonstrates an innovative serverless architecture pattern combining AWS Lambda with Amazon EFS for shared state management in distributed serverless systems.
