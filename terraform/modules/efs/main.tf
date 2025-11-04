# EFS Module - Shared Filesystem Infrastructure

# EFS File System with KMS Encryption
resource "aws_efs_file_system" "shared" {
  creation_token   = "${var.prefix}-efs-${var.environment}"
  encrypted        = true
  performance_mode = "generalPurpose"

  tags = {
    Name        = "${var.prefix}-efs"
    Environment = var.environment
  }
}


# EFS Mount Target in Private Subnet 1
resource "aws_efs_mount_target" "mount_1" {
  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = var.private_subnet_ids[0]
  security_groups = [var.efs_sg_id]
}

# EFS Mount Target in Private Subnet 2
resource "aws_efs_mount_target" "mount_2" {
  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = var.private_subnet_ids[1]
  security_groups = [var.efs_sg_id]
}


# EFS Access Point for Lambda Functions
resource "aws_efs_access_point" "lambda_ap" {
  file_system_id = aws_efs_file_system.shared.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/lambda"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name        = "${var.prefix}-lambda-access-point"
    Environment = var.environment
  }
}
