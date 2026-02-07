# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.prefix}"
  retention_in_days = 7

  tags = { Name = "${local.prefix}-logs" }
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "${local.prefix}-ecs"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = { Name = "${local.prefix}-ecs" }
}

# --- Task Definition ---
resource "aws_ecs_task_definition" "app" {
  family                   = "${local.prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = var.app_name
    image     = "${local.ecr_url}:${var.environment}-latest"
    essential = true

    portMappings = [{
      containerPort = var.app_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "ASPNETCORE_ENVIRONMENT", value = var.environment },
      { name = "ASPNETCORE_URLS", value = "http://+:${var.app_port}" }
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.app_port}/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${local.prefix}-task" }
}

# --- ECS Service ---
resource "aws_ecs_service" "app" {
  name            = "${local.prefix}-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.app_name
    container_port   = var.app_port
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = { Name = "${local.prefix}-svc" }
}
