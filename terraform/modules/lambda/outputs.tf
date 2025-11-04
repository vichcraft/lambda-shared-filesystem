# Lambda Module Outputs

output "producer_lambda_arn" {
  description = "ARN of the Producer Lambda function"
  value       = aws_lambda_function.producer.arn
}

output "producer_lambda_name" {
  description = "Name of the Producer Lambda function"
  value       = aws_lambda_function.producer.function_name
}

output "consumer_lambda_arn" {
  description = "ARN of the Consumer Lambda function"
  value       = aws_lambda_function.consumer.arn
}

output "consumer_lambda_name" {
  description = "Name of the Consumer Lambda function"
  value       = aws_lambda_function.consumer.function_name
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.lambda_efs_api.id
}

output "api_gateway_stage" {
  description = "API Gateway deployment stage"
  value       = aws_api_gateway_stage.prod.stage_name
}

output "ingest_endpoint" {
  description = "Full URL for the /ingest endpoint"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/ingest"
}

output "predict_endpoint" {
  description = "Full URL for the /predict endpoint"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/predict"
}
