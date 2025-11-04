# Lambda + EFS Proof-of-Concept

## What This System Does

This proof-of-concept demonstrates how multiple AWS Lambda functions can share state through a common Amazon EFS (Elastic File System) filesystem, enabling distributed serverless applications with persistent shared storage.

### System Components

**Producer Lambda Function**
- Triggered automatically when files are uploaded to S3 (models/ prefix)
- Downloads files from S3
- Writes files to the shared EFS filesystem at `/mnt/efs/models/`
- Uses atomic write operations (temporary file + rename) for data consistency

**Consumer Lambda Function**
- Triggered by HTTP POST requests via API Gateway
- Reads files from the shared EFS filesystem at `/mnt/efs/models/`
- Processes the files (calculates checksums, analyzes content)
- Writes results to `/mnt/efs/outputs/`
- Archives results to S3 (outputs/ prefix)

**Shared EFS Filesystem**
- Mounted at `/mnt/efs` on both Lambda functions
- Provides persistent storage that survives Lambda invocations
- Enables file-based communication between Lambda functions
- Supports concurrent access from multiple Lambda instances

### Data Flow

```
1. Upload file to S3 (models/ prefix)
   ↓
2. S3 event triggers Producer Lambda
   ↓
3. Producer downloads from S3 and writes to EFS
   ↓
4. File persists on EFS at /mnt/efs/models/
   ↓
5. HTTP POST to /predict endpoint triggers Consumer Lambda
   ↓
6. Consumer reads file from EFS
   ↓
7. Consumer processes file and writes result to EFS
   ↓
8. Result archived to S3 (outputs/ prefix)
```

### Key Capabilities

- **Shared State**: Multiple ephemeral Lambda functions access the same filesystem
- **Event-Driven**: S3 uploads automatically trigger processing
- **RESTful API**: HTTP endpoints for on-demand operations
- **Concurrent Access**: Multiple Lambda instances can read/write simultaneously
- **Persistence**: Files remain on EFS across Lambda invocations
- **Atomic Operations**: Safe concurrent writes using filesystem semantics

### Architecture

The system runs entirely within a VPC with:
- Two private subnets across different availability zones
- EFS mount targets in both availability zones for high availability
- Security groups controlling NFS traffic between Lambda and EFS
- S3 VPC Gateway Endpoint for efficient S3 access without internet connectivity
- API Gateway providing RESTful endpoints

This architecture validates that serverless functions can effectively use shared filesystem storage, combining the scalability of Lambda with the convenience of traditional file-based operations.
