# Lambda Module - Lambda Functions and API Gateway

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# Producer Lambda Execution Role
resource "aws_iam_role" "producer_lambda" {
  name = "${var.prefix}-producer-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.prefix}-producer-lambda-role"
  }
}

# Consumer Lambda Execution Role
resource "aws_iam_role" "consumer_lambda" {
  name = "${var.prefix}-consumer-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.prefix}-consumer-lambda-role"
  }
}

# Attach AWS managed policy for VPC access to Producer Lambda
resource "aws_iam_role_policy_attachment" "producer_vpc_access" {
  role       = aws_iam_role.producer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attach AWS managed policy for VPC access to Consumer Lambda
resource "aws_iam_role_policy_attachment" "consumer_vpc_access" {
  role       = aws_iam_role.consumer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# CloudWatch Logs policy for Producer Lambda
resource "aws_iam_role_policy" "producer_cloudwatch_logs" {
  name = "${var.prefix}-producer-cloudwatch-logs"
  role = aws_iam_role.producer_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.prefix}-producer-lambda:*"
      }
    ]
  })
}

# CloudWatch Logs policy for Consumer Lambda
resource "aws_iam_role_policy" "consumer_cloudwatch_logs" {
  name = "${var.prefix}-consumer-cloudwatch-logs"
  role = aws_iam_role.consumer_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.prefix}-consumer-lambda:*"
      }
    ]
  })
}


# EFS permissions policy for Producer Lambda
resource "aws_iam_role_policy" "producer_efs" {
  name = "${var.prefix}-producer-efs"
  role = aws_iam_role.producer_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = "arn:aws:elasticfilesystem:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:file-system/${var.efs_file_system_id}"
      }
    ]
  })
}

# EFS permissions policy for Consumer Lambda
resource "aws_iam_role_policy" "consumer_efs" {
  name = "${var.prefix}-consumer-efs"
  role = aws_iam_role.consumer_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = "arn:aws:elasticfilesystem:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:file-system/${var.efs_file_system_id}"
      }
    ]
  })
}


# S3 permissions policy for Producer Lambda
resource "aws_iam_role_policy" "producer_s3" {
  name = "${var.prefix}-producer-s3"
  role = aws_iam_role.producer_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${var.s3_bucket_arn}/models/*"
      }
    ]
  })
}

# S3 permissions policy for Consumer Lambda
resource "aws_iam_role_policy" "consumer_s3" {
  name = "${var.prefix}-consumer-s3"
  role = aws_iam_role.consumer_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${var.s3_bucket_arn}/outputs/*"
      }
    ]
  })
}


# ============================================================================
# Lambda Functions
# ============================================================================

# Create deployment package for Producer Lambda
data "archive_file" "producer_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda_code/producer"
  output_path = "${path.module}/../../lambda_code/producer.zip"
}

# Producer Lambda Function
resource "aws_lambda_function" "producer" {
  filename         = data.archive_file.producer_lambda.output_path
  function_name    = "${var.prefix}-producer-lambda"
  role             = aws_iam_role.producer_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.producer_lambda.output_base64sha256
  runtime          = "python3.11"
  memory_size      = 1024
  timeout          = 300

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  file_system_config {
    arn              = var.efs_access_point_arn
    local_mount_path = "/mnt/efs"
  }

  environment {
    variables = {
      EFS_MOUNT_PATH = "/mnt/efs"
      S3_BUCKET_NAME = var.s3_bucket_name
      MODELS_DIR     = "models"
      INPUTS_DIR     = "inputs"
      OUTPUTS_DIR    = "outputs"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.producer_vpc_access,
    aws_iam_role_policy.producer_cloudwatch_logs,
    aws_iam_role_policy.producer_efs,
    aws_iam_role_policy.producer_s3
  ]

  tags = {
    Name = "${var.prefix}-producer-lambda"
  }
}

# CloudWatch Log Group for Producer Lambda
resource "aws_cloudwatch_log_group" "producer_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.producer.function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.prefix}-producer-lambda-logs"
  }
}


# Create deployment package for Consumer Lambda
data "archive_file" "consumer_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda_code/consumer"
  output_path = "${path.module}/../../lambda_code/consumer.zip"
}

# Consumer Lambda Function
resource "aws_lambda_function" "consumer" {
  filename         = data.archive_file.consumer_lambda.output_path
  function_name    = "${var.prefix}-consumer-lambda"
  role             = aws_iam_role.consumer_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.consumer_lambda.output_base64sha256
  runtime          = "python3.11"
  memory_size      = 2048
  timeout          = 300

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  file_system_config {
    arn              = var.efs_access_point_arn
    local_mount_path = "/mnt/efs"
  }

  environment {
    variables = {
      EFS_MOUNT_PATH    = "/mnt/efs"
      S3_BUCKET_NAME    = var.s3_bucket_name
      ENABLE_S3_ARCHIVE = "true"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.consumer_vpc_access,
    aws_iam_role_policy.consumer_cloudwatch_logs,
    aws_iam_role_policy.consumer_efs,
    aws_iam_role_policy.consumer_s3
  ]

  tags = {
    Name = "${var.prefix}-consumer-lambda"
  }
}

# CloudWatch Log Group for Consumer Lambda
resource "aws_cloudwatch_log_group" "consumer_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.consumer.function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.prefix}-consumer-lambda-logs"
  }
}


# ============================================================================
# S3 Event Notification Configuration
# ============================================================================

# Lambda permission for S3 to invoke Producer Lambda
resource "aws_lambda_permission" "s3_invoke_producer" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.s3_bucket_arn
}

# S3 Bucket Notification to trigger Producer Lambda on ObjectCreated events
resource "aws_s3_bucket_notification" "producer_trigger" {
  bucket = var.s3_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.producer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "models/"
  }

  depends_on = [aws_lambda_permission.s3_invoke_producer]
}


# ============================================================================
# API Gateway REST API
# ============================================================================

# API Gateway REST API
resource "aws_api_gateway_rest_api" "lambda_efs_api" {
  name        = "${var.prefix}-lambda-efs-api"
  description = "API Gateway for Lambda + EFS POC"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.prefix}-lambda-efs-api"
  }
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id

  # Force redeployment when resources change
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.ingest.id,
      aws_api_gateway_resource.predict.id,
      aws_api_gateway_method.ingest_post.id,
      aws_api_gateway_method.predict_post.id,
      aws_api_gateway_integration.ingest.id,
      aws_api_gateway_integration.predict.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.ingest_post,
    aws_api_gateway_method.predict_post,
    aws_api_gateway_integration.ingest,
    aws_api_gateway_integration.predict,
  ]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.lambda_efs_api.id
  stage_name    = "prod"

  tags = {
    Name = "${var.prefix}-api-prod-stage"
  }
}


# ============================================================================
# API Gateway Resources and Methods
# ============================================================================

# /ingest resource
resource "aws_api_gateway_resource" "ingest" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id
  parent_id   = aws_api_gateway_rest_api.lambda_efs_api.root_resource_id
  path_part   = "ingest"
}

# POST /ingest method
resource "aws_api_gateway_method" "ingest_post" {
  rest_api_id   = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id   = aws_api_gateway_resource.ingest.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda integration for POST /ingest
resource "aws_api_gateway_integration" "ingest" {
  rest_api_id             = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id             = aws_api_gateway_resource.ingest.id
  http_method             = aws_api_gateway_method.ingest_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.producer.invoke_arn
}

# Lambda permission for API Gateway to invoke Producer
resource "aws_lambda_permission" "api_invoke_producer" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda_efs_api.execution_arn}/*/*"
}

# /predict resource
resource "aws_api_gateway_resource" "predict" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id
  parent_id   = aws_api_gateway_rest_api.lambda_efs_api.root_resource_id
  path_part   = "predict"
}

# POST /predict method
resource "aws_api_gateway_method" "predict_post" {
  rest_api_id   = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id   = aws_api_gateway_resource.predict.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda integration for POST /predict
resource "aws_api_gateway_integration" "predict" {
  rest_api_id             = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id             = aws_api_gateway_resource.predict.id
  http_method             = aws_api_gateway_method.predict_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.consumer.invoke_arn
}

# Lambda permission for API Gateway to invoke Consumer
resource "aws_lambda_permission" "api_invoke_consumer" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.consumer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda_efs_api.execution_arn}/*/*"
}


# ============================================================================
# CORS Configuration
# ============================================================================

# OPTIONS method for /ingest (CORS preflight)
resource "aws_api_gateway_method" "ingest_options" {
  rest_api_id   = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id   = aws_api_gateway_resource.ingest.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Mock integration for OPTIONS /ingest
resource "aws_api_gateway_integration" "ingest_options" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id = aws_api_gateway_resource.ingest.id
  http_method = aws_api_gateway_method.ingest_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method response for OPTIONS /ingest
resource "aws_api_gateway_method_response" "ingest_options" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id = aws_api_gateway_resource.ingest.id
  http_method = aws_api_gateway_method.ingest_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Integration response for OPTIONS /ingest
resource "aws_api_gateway_integration_response" "ingest_options" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id = aws_api_gateway_resource.ingest.id
  http_method = aws_api_gateway_method.ingest_options.http_method
  status_code = aws_api_gateway_method_response.ingest_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# OPTIONS method for /predict (CORS preflight)
resource "aws_api_gateway_method" "predict_options" {
  rest_api_id   = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id   = aws_api_gateway_resource.predict.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Mock integration for OPTIONS /predict
resource "aws_api_gateway_integration" "predict_options" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id = aws_api_gateway_resource.predict.id
  http_method = aws_api_gateway_method.predict_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method response for OPTIONS /predict
resource "aws_api_gateway_method_response" "predict_options" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id = aws_api_gateway_resource.predict.id
  http_method = aws_api_gateway_method.predict_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Integration response for OPTIONS /predict
resource "aws_api_gateway_integration_response" "predict_options" {
  rest_api_id = aws_api_gateway_rest_api.lambda_efs_api.id
  resource_id = aws_api_gateway_resource.predict.id
  http_method = aws_api_gateway_method.predict_options.http_method
  status_code = aws_api_gateway_method_response.predict_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}
