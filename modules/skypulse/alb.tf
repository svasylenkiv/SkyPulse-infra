# --- Application Load Balancer ---
resource "aws_lb" "main" {
  name               = "${local.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${local.prefix}-alb" }
}

# --- Stable Target Group ---
resource "aws_lb_target_group" "app" {
  name        = "${local.prefix}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "${local.prefix}-tg" }
}

# --- Canary Target Group ---
resource "aws_lb_target_group" "canary" {
  count = var.canary_enabled ? 1 : 0

  name        = "${local.prefix}-canary-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "${local.prefix}-canary-tg" }
}

# --- HTTP Listener ---
# When certificate_arn is set: redirect HTTP -> HTTPS
# When certificate_arn is not set: forward to target group(s) with optional canary weighting
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn != "" ? "redirect" : "forward"

    # Simple forward (when no certificate AND no canary)
    target_group_arn = var.certificate_arn == "" && !var.canary_enabled ? aws_lb_target_group.app.arn : null

    # Weighted forward (when no certificate AND canary enabled)
    dynamic "forward" {
      for_each = var.certificate_arn == "" && var.canary_enabled ? [1] : []
      content {
        target_group {
          arn    = aws_lb_target_group.app.arn
          weight = 100 - var.canary_weight
        }

        target_group {
          arn    = aws_lb_target_group.canary[0].arn
          weight = var.canary_weight
        }

        stickiness {
          enabled  = false
          duration = 1
        }
      }
    }

    # Redirect to HTTPS (when certificate is present)
    dynamic "redirect" {
      for_each = var.certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# --- HTTPS Listener (only when certificate_arn is provided) ---
# Supports weighted forwarding when canary is enabled
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "forward"

    # Simple forward (no canary)
    target_group_arn = !var.canary_enabled ? aws_lb_target_group.app.arn : null

    # Weighted forward (canary enabled)
    dynamic "forward" {
      for_each = var.canary_enabled ? [1] : []
      content {
        target_group {
          arn    = aws_lb_target_group.app.arn
          weight = 100 - var.canary_weight
        }

        target_group {
          arn    = aws_lb_target_group.canary[0].arn
          weight = var.canary_weight
        }

        stickiness {
          enabled  = false
          duration = 1
        }
      }
    }
  }
}
