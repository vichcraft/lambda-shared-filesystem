# Lambda + EFS POC - Root Terraform Configuration
# This configuration orchestrates all infrastructure modules

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Backend configuration for state management
  # For POC, using local backend. For production, use S3 backend.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "lambda-efs-poc"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# VPC Module - Creates network infrastructure
module "vpc" {
  source = "./modules/vpc"

  prefix      = var.prefix
  environment = var.environment
  region      = var.region
}

# EFS Module - Creates shared filesystem
module "efs" {
  source = "./modules/efs"

  prefix             = var.prefix
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  lambda_sg_id       = module.vpc.lambda_sg_id
  efs_sg_id          = module.vpc.efs_sg_id
}

# S3 Module - Creates object storage bucket
module "s3" {
  source = "./modules/s3"

  prefix      = var.prefix
  environment = var.environment
}

# Lambda Module - Creates Lambda functions and API Gateway
module "lambda" {
  source = "./modules/lambda"

  prefix               = var.prefix
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  lambda_sg_id         = module.vpc.lambda_sg_id
  efs_file_system_id   = module.efs.efs_file_system_id
  efs_access_point_arn = module.efs.efs_access_point_arn
  s3_bucket_name       = module.s3.bucket_name
  s3_bucket_arn        = module.s3.bucket_arn
}
