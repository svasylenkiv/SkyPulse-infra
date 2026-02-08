output "alb_dns_name" {
  description = "ALB DNS name (app URL)"
  value       = var.certificate_arn != "" ? "https://${aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing images"
  value       = local.ecr_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "sns_alerts_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "canary_service_name" {
  description = "Canary ECS service name (empty when canary is disabled)"
  value       = var.canary_enabled ? aws_ecs_service.canary[0].name : ""
}

output "canary_target_group_arn" {
  description = "Canary target group ARN (empty when canary is disabled)"
  value       = var.canary_enabled ? aws_lb_target_group.canary[0].arn : ""
}
