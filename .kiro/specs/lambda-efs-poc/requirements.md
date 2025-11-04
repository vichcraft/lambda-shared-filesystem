# Requirements Document

## Introduction

This document outlines the requirements for a proof-of-concept (POC) implementation demonstrating an innovative serverless architecture that combines AWS Lambda with Amazon EFS. The system will showcase how multiple ephemeral Lambda functions can share state through a common mounted filesystem, effectively creating a distributed serverless system with persistent shared storage. This POC serves as the implementation evidence for an academic paper on innovative cloud storage use cases.

The prototype will implement a representative use case that clearly demonstrates the core architectural pattern: one Lambda function writing data to EFS and another Lambda function reading and processing that data, all within a VPC with shared filesystem access. S3 is the system of record; EFS is the shared working set Lambda mounts at /mnt/efs via an EFS Access Point.

## Glossary

- **Lambda Function**: AWS Lambda serverless compute service that runs code in response to events without provisioning servers
- **EFS (Elastic File System)**: Amazon's scalable, elastic NFS file system that can be mounted by multiple compute resources simultaneously
- **VPC (Virtual Private Cloud)**: An isolated virtual network within AWS where resources can communicate securely
- **EFS Access Point**: An application-specific entry point into an EFS file system that enforces a user identity and root directory for Lambda access
- **Producer Lambda**: The Lambda function responsible for ingesting or generating data and writing it to the shared EFS filesystem
- **Consumer Lambda**: The Lambda function responsible for reading data from EFS and performing processing or inference operations
- **API Gateway**: AWS service that creates, publishes, and manages REST APIs to trigger Lambda functions
- **Infrastructure as Code (IaC)**: The practice of managing infrastructure through code files (using tools like Terraform, CDK, or CloudFormation)
- **Cold Start**: The initialization time when a Lambda function is invoked for the first time or after being idle
- **Mount Target**: The network interface through which EC2 instances and Lambda functions access an EFS file system within a VPC

## Requirements

### Requirement 1: Infrastructure Provisioning

**User Story:** As a developer, I want to provision the necessary AWS infrastructure using Infrastructure as Code, so that the POC environment can be created reproducibly and documented clearly for the paper.

#### Acceptance Criteria

1. THE Infrastructure Provisioning System SHALL create a VPC with two private subnets in different availability zones for Lambda and EFS communication
2. THE Infrastructure Provisioning System SHALL create an EFS file system with one mount target per subnet used by Lambda
3. THE Infrastructure Provisioning System SHALL create an EFS Access Point rooted at /lambda with POSIX uid:gid set to 1000:1000 and KMS encryption enabled
4. THE Infrastructure Provisioning System SHALL create security groups where SG-Lambda to SG-EFS allows TCP port 2049 traffic
5. THE Infrastructure Provisioning System SHALL create an S3 Gateway VPC Endpoint for private S3 access
6. THE Infrastructure Provisioning System SHALL output the EFS file system ID, Access Point ARN, security group IDs, subnet IDs, and S3 bucket name
7. WHERE Terraform is used as the IaC tool, THE Infrastructure Provisioning System SHALL organize resources into logical modules for VPC, EFS, and Lambda components

### Requirement 2: Producer Lambda Implementation (App1)

**User Story:** As a system architect, I want a Producer Lambda function that writes data to EFS, so that I can demonstrate the data ingestion pattern in the serverless architecture.

#### Acceptance Criteria

1. THE Producer Lambda SHALL mount the EFS file system at the path /mnt/efs during initialization
2. THE Producer Lambda SHALL create the directory schema /mnt/efs/models/ for model storage, /mnt/efs/inputs/ for optional user inputs, and /mnt/efs/outputs/ for Consumer results if the paths do not exist
3. WHEN invoked via API Gateway POST /ingest with JSON containing a key field or raw payload data, THE Producer Lambda SHALL accept the input data through the request payload
4. WHEN invoked by an S3 ObjectCreated event on the models/ prefix, THE Producer Lambda SHALL retrieve the object from S3 and write it to EFS
5. THE Producer Lambda SHALL write data to a temporary file and perform an atomic rename to the final path for idempotency
6. THE Producer Lambda SHALL handle objects up to 1 GB in size for the POC
7. IF a file with the same key already exists on EFS, THEN THE Producer Lambda SHALL return a 200 status code with the existing file identifier
8. THE Producer Lambda SHALL return a success response containing the file identifier and file path to the caller
9. IF the EFS mount fails during initialization, THEN THE Producer Lambda SHALL log structured JSON containing requestId, fileId, and stage with value "write", and return a 500 status code

### Requirement 3: Consumer Lambda Implementation (App2)

**User Story:** As a system architect, I want a Consumer Lambda function that reads and processes data from EFS, so that I can demonstrate how multiple Lambda functions share state through the filesystem.

#### Acceptance Criteria

1. THE Consumer Lambda SHALL mount the same EFS file system at the path /mnt/efs via the same Access Point during initialization
2. WHEN invoked via API Gateway with a file identifier and model name, THE Consumer Lambda SHALL read the corresponding file from the EFS filesystem
3. THE Consumer Lambda SHALL perform a processing operation on the file contents (such as transformation, analysis, or computation)
4. THE Consumer Lambda SHALL write the processed results to /mnt/efs/outputs/{fileId}.result on the EFS filesystem
5. THE Consumer Lambda SHALL optionally archive the result to S3 at s3://<bucket>/outputs/{fileId}.result
6. THE Consumer Lambda SHALL handle at least 10 parallel invocations reading the same model file from EFS concurrently
7. THE Consumer Lambda SHALL return JSON containing fileId, efsPath, optional s3Key, and durationMs to the caller
8. IF the requested file does not exist on EFS, THEN THE Consumer Lambda SHALL return a 404 status code with JSON containing error set to "NOT_FOUND" and the fileId

### Requirement 4: API Gateway Integration

**User Story:** As a user testing the POC, I want REST API endpoints to trigger the Lambda functions, so that I can easily demonstrate the system's functionality through HTTP requests.

#### Acceptance Criteria

1. THE API Gateway SHALL expose a POST /ingest endpoint that triggers the Producer Lambda function with a request body containing key or data fields
2. THE API Gateway SHALL expose a POST /predict endpoint that triggers the Consumer Lambda function with a request body containing fileId and model fields
3. THE API Gateway SHALL use Lambda proxy integration for both endpoints
4. WHEN a request is received, THE API Gateway SHALL pass the request payload and parameters to the appropriate Lambda function
5. THE API Gateway SHALL return the Lambda function's response to the client with appropriate HTTP status codes in standard JSON format
6. THE API Gateway SHALL enable CORS headers with Origins set to wildcard for POC browser-based testing

### Requirement 5: S3 System of Record and Eventing

**User Story:** As an operator, I want S3 to be the durable source and event trigger, so that ingestion can be automatic and aligned with the paper's architecture diagram.

#### Acceptance Criteria

1. THE Infrastructure Provisioning System SHALL create an S3 bucket with the naming pattern <prefix>-ml-models-bucket containing prefixes models/, inputs/, and outputs/
2. THE S3 Bucket SHALL configure an ObjectCreated event notification on the models/ prefix that triggers the Producer Lambda function
3. THE Producer Lambda IAM Role SHALL have s3:GetObject, s3:PutObject, and s3:ListBucket permissions scoped to the created bucket
4. THE Consumer Lambda IAM Role SHALL have s3:GetObject, s3:PutObject, and s3:ListBucket permissions scoped to the created bucket
5. THE S3 Bucket SHALL enable server-side encryption and block all public access

### Requirement 6: Demonstration and Validation

**User Story:** As a paper author, I want a comprehensive demonstration script that exercises the POC system, so that I can collect evidence and metrics for the paper's implementation section.

#### Acceptance Criteria

1. THE Demonstration Script SHALL invoke the Producer Lambda endpoint with sample data and capture the response
2. THE Demonstration Script SHALL invoke the Consumer Lambda endpoint with the file identifier from the Producer response
3. THE Demonstration Script SHALL verify that data written by the Producer is successfully read by the Consumer
4. THE Demonstration Script SHALL measure and report cold start timing versus warm invocation timing for the /predict endpoint
5. THE Demonstration Script SHALL perform a parallel test invoking /predict 10 times concurrently and verify that all invocations successfully read the shared model from EFS
6. THE Demonstration Script SHALL generate an evidence bundle containing EFS Access Point configuration screenshot, Lambda configuration showing EFS mount details, CloudWatch logs for both functions, and S3 outputs/ prefix listing
7. THE Demonstration Script SHALL output results in a format suitable for inclusion in the paper (such as JSON or formatted text)

### Requirement 7: Documentation and Deployment Guide

**User Story:** As a paper reader or reviewer, I want clear documentation on how to deploy and run the POC, so that I can reproduce the results and validate the claims in the paper.

#### Acceptance Criteria

1. THE Documentation SHALL provide step-by-step instructions for deploying the infrastructure using the IaC tool
2. THE Documentation SHALL list all prerequisites including required AWS permissions, tools, and dependencies
3. THE Documentation SHALL explain how to invoke the API endpoints and interpret the responses
4. THE Documentation SHALL include a cleanup procedure for destroying all created AWS resources
5. THE Documentation SHALL document the expected costs for running the POC and any AWS free tier considerations
