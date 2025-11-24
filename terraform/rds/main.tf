terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Data sources
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["multi-tenant-vpc-budget"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Name"
    values = ["multi-tenant-public-*"]
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "multi-tenant-rds-sg-budget"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = data.aws_vpc.main.id

  # Allow PostgreSQL from VPC
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "multi-tenant-rds-sg-budget"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "multi-tenant-db-subnet-budget"
  subnet_ids = data.aws_subnets.public.ids

  tags = {
    Name = "multi-tenant-db-subnet-group-budget"
  }
}

# Parameter Group
resource "aws_db_parameter_group" "postgres" {
  name   = "multi-tenant-postgres14-budget"
  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name = "multi-tenant-postgres-params-budget"
  }
}

# RDS PostgreSQL Instance - BUDGET VERSION
resource "aws_db_instance" "main" {
  identifier     = "multi-tenant-postgres-budget"
  engine         = "postgres"
  engine_version = "14.20"
  
  # BUDGET: db.t3.micro instead of db.t3.medium
  instance_class = "db.t3.micro"

  # BUDGET: 20GB instead of 100GB
  allocated_storage     = 20
  max_allocated_storage = 100  # Auto-scale if needed
  storage_type          = "gp3"  # Cheaper than gp2
  storage_encrypted     = true

  db_name  = "multitenantdb"
  username = "dbadmin"
  password = var.db_password  # Store in variables, never commit!

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  # BUDGET: Single-AZ (no Multi-AZ)
  multi_az = false
  publicly_accessible = false

  # BUDGET: 3-day backups instead of 7
  backup_retention_period = 3
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"

  # Minimal logging
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # BUDGET: No Performance Insights
  performance_insights_enabled = false

  # Deletion protection OFF for dev
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name        = "multi-tenant-postgres-budget"
    Environment = "dev"
    CostCenter  = "budget-optimized"
  }
}
