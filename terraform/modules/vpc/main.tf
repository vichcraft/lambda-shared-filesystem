# VPC Module - Network Infrastructure

# VPC Resource
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.prefix}-vpc"
    Environment = var.environment
  }
}

# Private Subnet 1 (us-east-1a)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.region}a"

  tags = {
    Name        = "${var.prefix}-private-subnet-1"
    Environment = var.environment
  }
}

# Private Subnet 2 (us-west-1c for us-west-1, us-east-1b for us-east-1)
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.region == "us-west-1" ? "${var.region}c" : "${var.region}b"

  tags = {
    Name        = "${var.prefix}-private-subnet-2"
    Environment = var.environment
  }
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.prefix}-private-rt"
    Environment = var.environment
  }
}

# Route Table Association for Private Subnet 1
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

# Route Table Association for Private Subnet 2
resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}


# S3 Gateway VPC Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name        = "${var.prefix}-s3-endpoint"
    Environment = var.environment
  }
}


# Security Group for Lambda Functions
resource "aws_security_group" "lambda" {
  name        = "${var.prefix}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.prefix}-lambda-sg"
    Environment = var.environment
  }
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.prefix}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.prefix}-efs-sg"
    Environment = var.environment
  }
}

# Security Group Rule: Lambda egress to EFS
resource "aws_security_group_rule" "lambda_to_efs" {
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.efs.id
  security_group_id        = aws_security_group.lambda.id
  description              = "Allow NFS traffic to EFS"
}

# Security Group Rule: Lambda egress to all for AWS API calls
resource "aws_security_group_rule" "lambda_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lambda.id
  description       = "Allow all outbound traffic for AWS API calls"
}

# Security Group Rule: EFS ingress from Lambda
resource "aws_security_group_rule" "efs_from_lambda" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
  security_group_id        = aws_security_group.efs.id
  description              = "Allow NFS traffic from Lambda"
}
