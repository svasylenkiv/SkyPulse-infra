terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "skypulse-tf-state"
    key            = "stg/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "skypulse-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = var.managed_by
      Environment = var.environment
    }
  }
}

variable "aws_region" {
  type = string
}

variable "app_name" {
  type = string
}

variable "project" {
  type = string
}

variable "managed_by" {
  type = string
}

variable "environment" {
  type    = string
  default = "stg"
}

variable "ecr_repository_url" {
  description = "ECR repository URL (from dev environment output)"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional)"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

module "skypulse" {
  source = "../../modules/skypulse"

  aws_region          = var.aws_region
  environment         = var.environment
  app_name            = var.app_name
  cpu                 = 256
  memory              = 512
  desired_count       = 1
  min_capacity        = 1
  max_capacity        = 1
  cpu_target_percent  = 70
  create_ecr          = false
  ecr_repository_url  = var.ecr_repository_url
  certificate_arn     = var.certificate_arn
  alert_email         = var.alert_email
}
