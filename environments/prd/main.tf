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
    key            = "prd/terraform.tfstate"
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
  default = "prd"
}

variable "ecr_repository_url" {
  description = "ECR repository URL (from dev environment output)"
  type        = string
}

module "skypulse" {
  source = "../../modules/skypulse"

  aws_region          = var.aws_region
  environment         = var.environment
  app_name            = var.app_name
  cpu                 = 512
  memory              = 1024
  desired_count       = 2
  min_capacity        = 2
  max_capacity        = 4
  cpu_target_percent  = 60
  create_ecr          = false
  ecr_repository_url  = var.ecr_repository_url
}
