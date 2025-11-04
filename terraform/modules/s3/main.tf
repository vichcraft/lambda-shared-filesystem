# S3 Module - Object Storage Infrastructure
# Creates S3 bucket for model storage and results archiving

# Get current AWS account ID for unique bucket naming
data "aws_caller_identity" "current" {}

# S3 Bucket for models, inputs, and outputs
resource "aws_s3_bucket" "ml_models" {
  bucket = "${var.prefix}-lambda-efs-poc-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.prefix}-ml-models-bucket"
  }
}

# Enable server-side encryption (AES-256)
resource "aws_s3_bucket_server_side_encryption_configuration" "ml_models" {
  bucket = aws_s3_bucket.ml_models.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "ml_models" {
  bucket = aws_s3_bucket.ml_models.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforce HTTPS only
resource "aws_s3_bucket_policy" "ml_models" {
  bucket = aws_s3_bucket.ml_models.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceHTTPSOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.ml_models.arn,
          "${aws_s3_bucket.ml_models.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Create prefix structure using objects
# Note: S3 doesn't have true "folders", but we create placeholder objects
# to establish the prefix structure for documentation purposes
resource "aws_s3_object" "models_prefix" {
  bucket  = aws_s3_bucket.ml_models.id
  key     = "models/.gitkeep"
  content = "This directory stores model files"
}

resource "aws_s3_object" "inputs_prefix" {
  bucket  = aws_s3_bucket.ml_models.id
  key     = "inputs/.gitkeep"
  content = "This directory stores input data"
}

resource "aws_s3_object" "outputs_prefix" {
  bucket  = aws_s3_bucket.ml_models.id
  key     = "outputs/.gitkeep"
  content = "This directory stores processing results"
}
