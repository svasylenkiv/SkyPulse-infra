# --- SNS Topic for Alerts ---
resource "aws_sns_topic" "alerts" {
  name = "${local.prefix}-alerts"

  tags = { Name = "${local.prefix}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
