# Outputs for Lambda + EFS POC
# These outputs capture deployment information for testing and documentation

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "lambda_security_group_id" {
  description = "ID of the Lambda security group"
  value       = module.vpc.lambda_sg_id
}

output "efs_security_group_id" {
  description = "ID of the EFS security group"
  value       = module.vpc.efs_sg_id
}

# EFS Outputs
output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = module.efs.efs_file_system_id
}

output "efs_access_point_arn" {
  description = "ARN of the EFS Access Point for Lambda"
  value       = module.efs.efs_access_point_arn
}

output "efs_access_point_id" {
  description = "ID of the EFS Access Point"
  value       = module.efs.efs_access_point_id
}

# S3 Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.s3.bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = module.s3.bucket_arn
}

# Lambda Outputs
output "producer_lambda_arn" {
  description = "ARN of the Producer Lambda function"
  value       = module.lambda.producer_lambda_arn
}

output "consumer_lambda_arn" {
  description = "ARN of the Consumer Lambda function"
  value       = module.lambda.consumer_lambda_arn
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = module.lambda.api_gateway_url
}

output "api_gateway_stage" {
  description = "API Gateway deployment stage"
  value       = module.lambda.api_gateway_stage
}

# Convenience Outputs for Testing
output "ingest_endpoint" {
  description = "Full URL for the /ingest endpoint"
  value       = "${module.lambda.api_gateway_url}/ingest"
}

output "predict_endpoint" {
  description = "Full URL for the /predict endpoint"
  value       = "${module.lambda.api_gateway_url}/predict"
}

# Summary Output for Easy Reference
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    region             = var.region
    environment        = var.environment
    vpc_id             = module.vpc.vpc_id
    efs_file_system_id = module.efs.efs_file_system_id
    s3_bucket_name     = module.s3.bucket_name
    api_gateway_url    = module.lambda.api_gateway_url
    ingest_endpoint    = "${module.lambda.api_gateway_url}/ingest"
    predict_endpoint   = "${module.lambda.api_gateway_url}/predict"
  }
}
