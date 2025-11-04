# EFS Module Outputs

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.shared.id
}

output "efs_access_point_arn" {
  description = "ARN of the EFS Access Point"
  value       = aws_efs_access_point.lambda_ap.arn
}

output "efs_access_point_id" {
  description = "ID of the EFS Access Point"
  value       = aws_efs_access_point.lambda_ap.id
}
