terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend config — bucket and dynamodb_table are passed via
  # -backend-config in the workflow (derived from app_name in common.tfvars)
  backend "s3" {
    key     = "dev/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
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
  default = "dev"
}

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

module "skypulse" {
  source = "../../modules/skypulse"

  aws_region         = var.aws_region
  environment        = var.environment
  app_name           = var.app_name
  cpu                = 256
  memory             = 512
  desired_count      = 2
  min_capacity       = 2
  max_capacity       = 4
  cpu_target_percent = 70
  create_ecr         = true
  alert_email        = var.alert_email

  # Canary deployment (set canary_enabled = true and canary_weight > 0 to activate)
  canary_enabled = true
  canary_weight  = 10
}
