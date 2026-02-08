variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prd)"
  type        = string
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "skypulse"
}

variable "app_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Fargate task CPU (in CPU units)"
  type        = number
}

variable "memory" {
  description = "Fargate task memory (in MiB)"
  type        = number
}

variable "desired_count" {
  description = "Initial number of running tasks"
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum number of tasks (autoscaling)"
  type        = number
}

variable "max_capacity" {
  description = "Maximum number of tasks (autoscaling)"
  type        = number
}

variable "cpu_target_percent" {
  description = "Target CPU utilization for autoscaling (%)"
  type        = number
  default     = 70
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. When set, HTTPS listener is created and HTTP redirects to HTTPS."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
}

variable "create_ecr" {
  description = "Whether to create ECR repository (set true only in one environment)"
  type        = bool
  default     = false
}

variable "ecr_repository_url" {
  description = "ECR repository URL (when create_ecr = false, pass from shared)"
  type        = string
  default     = ""
}

# --- Canary Deployment ---

variable "canary_enabled" {
  description = "Enable canary deployment (creates canary target group and ECS service)"
  type        = bool
  default     = false
}

variable "canary_weight" {
  description = "Traffic weight for canary target group (0-100). Stable gets (100 - canary_weight)."
  type        = number
  default     = 0

  validation {
    condition     = var.canary_weight >= 0 && var.canary_weight <= 100
    error_message = "canary_weight must be between 0 and 100."
  }
}

variable "canary_image_tag" {
  description = "Docker image tag for canary task definition. Defaults to <environment>-canary."
  type        = string
  default     = ""
}
