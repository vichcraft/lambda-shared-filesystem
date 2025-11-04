# Implementation Plan

This document outlines the implementation tasks for building the Lambda + EFS proof-of-concept. Each task builds incrementally on previous work, with all code integrated into a working system.

## Task List

- [x] 1. Set up project structure and Terraform foundation
  - Create directory structure for Terraform modules (vpc, efs, s3, lambda)
  - Create root Terraform configuration with provider and backend setup
  - Define input variables (region, prefix, environment)
  - Create outputs file for capturing deployment information
  - _Requirements: 1.1, 1.6, 1.7_

- [x] 2. Implement VPC infrastructure module
  - [x] 2.1 Create VPC with two private subnets in different availability zones
    - Write Terraform code for VPC resource with CIDR 10.0.0.0/16
    - Create private subnet 1 in us-east-1a (10.0.1.0/24)
    - Create private subnet 2 in us-east-1b (10.0.2.0/24)
    - Create route tables for private subnets
    - _Requirements: 1.1_

  - [x] 2.2 Create S3 Gateway VPC Endpoint
    - Write Terraform code for S3 Gateway endpoint
    - Associate endpoint with private subnet route tables
    - _Requirements: 1.5_

  - [x] 2.3 Create security groups for Lambda and EFS
    - Create sg-lambda security group with egress rules
    - Create sg-efs security group with ingress rule for TCP 2049 from sg-lambda
    - _Requirements: 1.4_

  - [x] 2.4 Add VPC module outputs
    - Output VPC ID, subnet IDs, and security group IDs
    - _Requirements: 1.6_

- [x] 3. Implement EFS infrastructure module
  - [x] 3.1 Create EFS file system with encryption
    - Write Terraform code for EFS file system resource
    - Enable KMS encryption
    - Set performance mode to General Purpose
    - _Requirements: 1.2, 1.3_

  - [x] 3.2 Create EFS mount targets
    - Create mount target in private subnet 1
    - Create mount target in private subnet 2
    - Attach sg-efs security group to mount targets
    - _Requirements: 1.2_

  - [x] 3.3 Create EFS Access Point
    - Write Terraform code for access point rooted at /lambda
    - Configure POSIX user with uid:gid 1000:1000
    - Set directory permissions to 755
    - _Requirements: 1.3_

  - [x] 3.4 Add EFS module outputs
    - Output EFS file system ID and Access Point ARN
    - _Requirements: 1.6_

- [x] 4. Implement S3 infrastructure module
  - [x] 4.1 Create S3 bucket with encryption and security
    - Write Terraform code for S3 bucket with naming pattern
    - Enable server-side encryption (AES-256)
    - Block all public access
    - Create prefixes: models/, inputs/, outputs/
    - _Requirements: 5.1, 5.5_

  - [x] 4.2 Add S3 module outputs
    - Output bucket name and bucket ARN
    - _Requirements: 1.6_

- [x] 5. Implement Producer Lambda function code
  - [x] 5.1 Create Lambda handler and directory management
    - Write lambda_function.py with handler function
    - Implement ensure_directories() to create /mnt/efs/{models,inputs,outputs}
    - Add environment variable handling for EFS_MOUNT_PATH
    - _Requirements: 2.1, 2.2_

  - [x] 5.2 Implement S3 event handling
    - Write handle_s3_event() to parse S3 ObjectCreated events
    - Implement download_from_s3() using boto3
    - Add file size validation (max 1 GB)
    - _Requirements: 2.4, 2.6_

  - [x] 5.3 Implement API Gateway event handling
    - Write handle_api_event() to parse API Gateway proxy events
    - Handle JSON body with "key" or "data" fields
    - Validate request payload
    - _Requirements: 2.3_

  - [x] 5.4 Implement atomic file writing to EFS
    - Write write_to_efs_atomic() function
    - Create temporary file with unique name
    - Perform atomic rename to final path
    - Implement idempotency check (return existing file if present)
    - _Requirements: 2.5, 2.7_

  - [x] 5.5 Implement response formatting and error handling
    - Create success response with fileId, efsPath, s3Key, sizeBytes
    - Implement structured error logging with requestId, fileId, stage
    - Handle EFS mount failures with 500 status code
    - _Requirements: 2.8, 2.9_

- [x] 6. Implement Consumer Lambda function code
  - [x] 6.1 Create Lambda handler and request parsing
    - Write lambda_function.py with handler function
    - Parse API Gateway proxy event body (fileId, model)
    - Add environment variable handling
    - _Requirements: 3.1, 3.2_

  - [x] 6.2 Implement model loading from EFS
    - Write load_model_from_efs() to read file from /mnt/efs/models/
    - Handle file not found with 404 response
    - Return structured error JSON with "NOT_FOUND" and fileId
    - _Requirements: 3.2, 3.8_

  - [x] 6.3 Implement processing logic
    - Write process_inference() function with simple computation
    - Calculate file metadata (size, checksum)
    - Measure processing duration
    - _Requirements: 3.3_

  - [x] 6.4 Implement result writing and S3 archiving
    - Write result to /mnt/efs/outputs/{fileId}.result
    - Implement optional archive_to_s3() function
    - Check ENABLE_S3_ARCHIVE environment variable
    - _Requirements: 3.4, 3.5_

  - [x] 6.5 Implement response formatting
    - Create JSON response with fileId, efsPath, s3Key, durationMs, result
    - Add timing metrics to response
    - _Requirements: 3.7_

- [x] 7. Implement Lambda infrastructure module
  - [x] 7.1 Create IAM roles for Lambda functions
    - Create Producer Lambda execution role
    - Create Consumer Lambda execution role
    - Attach AWSLambdaVPCAccessExecutionRole managed policy
    - Add CloudWatch Logs permissions
    - _Requirements: 2.1, 3.1_

  - [x] 7.2 Add EFS permissions to IAM roles
    - Add elasticfilesystem:ClientMount to both roles
    - Add elasticfilesystem:ClientWrite to both roles
    - _Requirements: 2.1, 3.1_

  - [x] 7.3 Add S3 permissions to IAM roles
    - Add s3:GetObject, s3:ListBucket to Producer role (scoped to bucket)
    - Add s3:PutObject to Producer role for models/ prefix
    - Add s3:GetObject, s3:PutObject to Consumer role (scoped to outputs/)
    - _Requirements: 5.3, 5.4_

  - [x] 7.4 Create Producer Lambda function resource
    - Write Terraform code for Lambda function
    - Set runtime to python3.11, memory to 1024 MB, timeout to 300s
    - Configure VPC attachment with private subnets and sg-lambda
    - Configure EFS mount at /mnt/efs using Access Point ARN
    - Set environment variables (EFS_MOUNT_PATH, S3_BUCKET_NAME, etc.)
    - Create deployment package from lambda_code/producer/
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 7.5 Create Consumer Lambda function resource
    - Write Terraform code for Lambda function
    - Set runtime to python3.11, memory to 2048 MB, timeout to 300s
    - Configure VPC attachment with private subnets and sg-lambda
    - Configure EFS mount at /mnt/efs using same Access Point ARN
    - Set environment variables (EFS_MOUNT_PATH, S3_BUCKET_NAME, ENABLE_S3_ARCHIVE)
    - Create deployment package from lambda_code/consumer/
    - _Requirements: 3.1, 3.2, 3.6_

  - [x] 7.6 Configure S3 event notification to Producer Lambda
    - Add Lambda permission for S3 to invoke Producer
    - Configure S3 bucket notification for ObjectCreated on models/ prefix
    - Wire Producer Lambda ARN to S3 event
    - _Requirements: 5.2_

  - [x] 7.7 Create API Gateway REST API
    - Write Terraform code for API Gateway REST API
    - Create deployment stage "prod"
    - _Requirements: 4.1, 4.2_

  - [x] 7.8 Create API Gateway endpoints
    - Create POST /ingest endpoint with Lambda proxy integration to Producer
    - Create POST /predict endpoint with Lambda proxy integration to Consumer
    - Add Lambda invoke permissions for API Gateway
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 7.9 Configure CORS on API Gateway
    - Enable CORS with wildcard origins for POC
    - Allow POST and OPTIONS methods
    - Allow Content-Type, X-Amz-Date, Authorization headers
    - _Requirements: 4.6_

  - [x] 7.10 Add Lambda module outputs
    - Output API Gateway URL, Producer Lambda ARN, Consumer Lambda ARN
    - _Requirements: 1.6_

- [x] 8. Create demonstration and testing script
  - [x] 8.1 Create demonstration script structure
    - Write demonstration.py with argument parsing for config file
    - Load Terraform outputs JSON
    - Set up logging and result collection
    - _Requirements: 6.1, 6.7_

  - [x] 8.2 Implement basic API tests
    - Write test_producer_api() to POST sample data to /ingest
    - Write test_consumer_api() to POST to /predict with fileId
    - Verify responses and status codes
    - _Requirements: 6.1, 6.2, 6.3_

  - [x] 8.3 Implement cold vs warm timing test
    - Invoke /predict endpoint for first time (cold start)
    - Wait 2 seconds and invoke again (warm)
    - Measure and compare durations
    - _Requirements: 6.4_

  - [x] 8.4 Implement concurrent access test
    - Use concurrent.futures to invoke /predict 10 times in parallel
    - Verify all invocations succeed
    - Calculate average and max duration
    - _Requirements: 6.5_

  - [x] 8.5 Implement evidence collection
    - Query CloudWatch Logs for both Lambda functions
    - Document EFS Access Point configuration
    - List S3 outputs/ prefix contents
    - _Requirements: 6.6_

  - [x] 8.6 Implement report generation
    - Format results as JSON with timestamps and metrics
    - Output to file suitable for paper inclusion
    - Include all test results and evidence paths
    - _Requirements: 6.7_

- [x] 9. Create documentation
  - [x] 9.1 Write deployment guide (README.md)
    - Document prerequisites (AWS CLI, Terraform, Python)
    - Provide step-by-step deployment instructions
    - Include terraform init, plan, apply commands
    - _Requirements: 7.1, 7.2_

  - [x] 9.2 Document API usage
    - Provide example curl commands for /ingest and /predict
    - Show expected request and response formats
    - Document error responses
    - _Requirements: 7.3_

  - [x] 9.3 Document cleanup procedure
    - Provide terraform destroy instructions
    - Note any manual cleanup steps (CloudWatch logs)
    - _Requirements: 7.4_

  - [x] 9.4 Document costs and AWS free tier
    - List estimated monthly costs
    - Highlight free tier benefits
    - Provide cost optimization tips
    - _Requirements: 7.5_

- [x] 10. Integration testing and validation
  - [x] 10.1 Deploy infrastructure to AWS test account
    - Run terraform apply
    - Verify all resources created successfully
    - Capture outputs
    - _Requirements: All infrastructure requirements_

  - [x] 10.2 Run demonstration script
    - Execute demonstration.py with outputs
    - Verify all tests pass
    - Collect metrics and evidence
    - _Requirements: 6.1-6.7_

  - [x] 10.3 Validate end-to-end flow
    - Upload model file to S3 models/ prefix
    - Verify Producer Lambda triggered automatically
    - Verify file appears on EFS
    - Call /predict endpoint
    - Verify Consumer reads from EFS and returns result
    - _Requirements: 2.4, 3.2, 5.2_

  - [x] 10.4 Generate final evidence bundle for paper
    - Collect all CloudWatch logs
    - Screenshot EFS Access Point configuration
    - Screenshot Lambda EFS mount configuration
    - Export demonstration script results
    - Package for paper inclusion
    - _Requirements: 6.6_
