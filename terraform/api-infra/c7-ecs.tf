# ============================================================
# c7-ecs.tf
# ECS Cluster, ECR Repository, Task Definitions, ECS Service,
# Service Discovery, and ECS Memory Alarm
# ============================================================

# ------------------------------------------------------------
# ECR Repository — stores Docker images for the API
# ------------------------------------------------------------

resource "aws_ecr_repository" "ecr-repo" {
  name = "${var.environment}-api-repo"
}

# ------------------------------------------------------------
# ECS Cluster — Fargate with Container Insights enabled
# Container Insights provides CPU/memory/network metrics per task
# ------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-fargate-cluster"

  setting {
    name  = "containerInsights"
    value = "enhanced" # Enhanced gives per-task metrics
  }
}

# ------------------------------------------------------------
# API Task Container Definition (rendered from template)
# Template lives at templates/ecs/api_app.json.tpl
# ------------------------------------------------------------

locals {
  api_app = templatefile("${path.module}/templates/ecs/api_app.json.tpl", {
    app_image      = "${var.project_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.ecr-repo.name}:latest"
    app_port       = var.app_port
    fargate_cpu    = var.fargate_cpu
    fargate_memory = var.fargate_memory
    aws_region     = var.aws_region
    environment    = var.environment
    jwt_secret_arn = var.JWT_secret_arn
  })
}

# ------------------------------------------------------------
# API Fargate Task Definition
# ------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.environment}-api-task"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  container_definitions    = local.api_app
}

# Data source to resolve the current active revision
data "aws_ecs_task_definition" "app" {
  task_definition = aws_ecs_task_definition.app.family
}

# ------------------------------------------------------------
# Service Discovery (optional)
# Registers the API with an existing Cloud Map namespace so
# other ECS services can reach it via DNS (api.<namespace>).
# Controlled by var.enable_service_discovery.
# ------------------------------------------------------------

resource "aws_service_discovery_service" "api" {
  count = var.enable_service_discovery ? 1 : 0
  name  = "api"

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_config {
    failure_threshold = 1
  }

  tags = {
    Environment = var.environment
    Service     = "api"
  }
}

# ------------------------------------------------------------
# ECS Service — runs and maintains desired API task count
# Uses the higher of the Terraform-defined or deployed revision
# to avoid re-deploying during apply when no code changed.
# ------------------------------------------------------------

resource "aws_ecs_service" "main" {
  name          = "${var.environment}-api-service"
  cluster       = aws_ecs_cluster.main.id
  desired_count = var.api_desired_instances_count
  launch_type   = "FARGATE"

  # Pin to the larger of Terraform or live revision to prevent downgrade
  task_definition = "${replace(aws_ecs_task_definition.app.arn, "/:\\d*$/", "")}:${max(aws_ecs_task_definition.app.revision, data.aws_ecs_task_definition.app.revision)}"

  # AZ rebalancing: ECS redistributes tasks across AZs during failures
  availability_zone_rebalancing = "ENABLED"

  # Prevent auto-scaling from being overwritten on every apply
  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    # Use shared SG for cross-service communication when enabled
    security_groups  = var.use_shared_security_group ? [var.shared_security_group_id] : [aws_security_group.ecs_tasks.id]
    subnets          = aws_subnet.private.*.id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.id
    container_name   = "${var.environment}-api"
    container_port   = var.app_port
  }

  # Give the container 3 minutes to pass health checks before ALB kills it
  health_check_grace_period_seconds = 180

  # Register with Cloud Map for service-to-service DNS resolution
  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.api[0].arn
    }
  }

  depends_on = [
    aws_alb_listener.external_alb_listener_443,
    aws_iam_role_policy_attachment.ecs_task_execution_role,
  ]
}

# ------------------------------------------------------------
# ECS Memory Alarm
# Triggers when memory utilization exceeds 85% sustained for
# 2 evaluation periods (2 minutes). Sends alert to SNS.
# ------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ecs_memory_alarm" {
  alarm_name          = "${var.environment}-ECS-high-memory-utilization-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "ECS Fargate memory utilization exceeded 85%"
  alarm_actions       = [var.sns_topic]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }
}
