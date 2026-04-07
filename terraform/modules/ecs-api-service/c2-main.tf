# =============================================================================
# ecs-api-service module — core infrastructure
#
# Provisions a complete ALB-backed Fargate HTTP service:
#   ECR repo → CloudWatch log group → ECS task def → ALB target group +
#   listener rule → ECS service (with circuit breaker + AZ rebalancing) →
#   optional service-discovery A record → optional App Auto Scaling (CPU,
#   memory, request-count) → optional CloudWatch alarms
# =============================================================================

locals {
  full_service_name = "${var.service_name}-service"
  root_name         = var.service_name
}

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "service_repo" {
  name                 = "${var.environment}-${local.full_service_name}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = var.enable_ecr_image_scanning
  }

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}-repo"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "service_logs" {
  name              = "/ecs/${var.environment}-${local.full_service_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}-logs"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

# Read back the latest active revision — CI may have bumped it ahead of Terraform.
# max() below ensures neither side can revert the other.
data "aws_ecs_task_definition" "service_task" {
  task_definition = aws_ecs_task_definition.service_task.family
}

resource "aws_ecs_task_definition" "service_task" {
  family                   = "${var.environment}-${local.full_service_name}-task"
  execution_role_arn       = local.task_execution_role_arn
  task_role_arn            = local.task_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_size
  }

  container_definitions = jsonencode([{
    name      = "${var.environment}-${local.full_service_name}"
    image     = "${aws_ecr_repository.service_repo.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = concat([
      { name = "NODE_ENV",    value = var.environment == "prod" ? "production" : "staging" },
      { name = "PORT",        value = tostring(var.container_port) },
      { name = "AWS_REGION",  value = var.aws_region },
    ], var.additional_env_vars)

    environmentFiles = var.env_file_arn != "" ? [{
      value = var.env_file_arn
      type  = "s3"
    }] : []

    secrets = var.secrets_arns

    healthCheck = var.enable_container_health_check ? {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    } : null

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    ulimits = var.enable_increased_ulimits ? [{
      name      = "nofile"
      softLimit = 65536
      hardLimit = 65536
    }] : []

    ephemeralStorage = {
      sizeInGiB = var.ephemeral_storage_size
    }
  }])

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}-task"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# ALB Target Group + Listener Rule
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "service_tg" {
  name        = "${var.environment}-${local.full_service_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  deregistration_delay = var.deregistration_delay

  stickiness {
    type            = "lb_cookie"
    enabled         = var.enable_stickiness
    cookie_duration = var.stickiness_duration
  }

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}-tg"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_lb_listener_rule" "service_rule" {
  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_tg.arn
  }

  dynamic "condition" {
    for_each = length(var.path_patterns) > 0 ? [1] : []
    content {
      path_pattern { values = var.path_patterns }
    }
  }

  dynamic "condition" {
    for_each = length(var.host_headers) > 0 ? [1] : []
    content {
      host_header { values = var.host_headers }
    }
  }

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}-rule"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "service" {
  name          = "${var.environment}-${local.full_service_name}"
  cluster       = var.ecs_cluster_id
  desired_count = var.desired_count
  launch_type   = "FARGATE"

  # Use the higher of Terraform-managed or CI-bumped revision
  task_definition = "${replace(aws_ecs_task_definition.service_task.arn, "/:\\d*$/", "")}:${max(aws_ecs_task_definition.service_task.revision, data.aws_ecs_task_definition.service_task.revision)}"

  availability_zone_rebalancing      = "ENABLED"
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.health_check_grace_period

  deployment_circuit_breaker {
    enable   = var.enable_circuit_breaker
    rollback = var.enable_circuit_breaker_rollback
  }

  network_configuration {
    security_groups  = var.security_group_ids
    subnets          = var.subnet_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.service_tg.arn
    container_name   = "${var.environment}-${local.full_service_name}"
    container_port   = var.container_port
  }

  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.service[0].arn
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.enable_capacity_providers ? var.capacity_provider_strategy : []
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener_rule.service_rule,
    aws_iam_role_policy_attachment.task_execution_role_policy,
  ]

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# Service Discovery (optional)
# -----------------------------------------------------------------------------

resource "aws_service_discovery_service" "service" {
  count = var.enable_service_discovery ? 1 : 0

  name = local.root_name

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}-discovery"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# App Auto Scaling
# -----------------------------------------------------------------------------

resource "aws_appautoscaling_target" "service_scaling_target" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.service]
}

resource "aws_appautoscaling_policy" "cpu_scaling_policy" {
  count = var.enable_autoscaling && var.enable_cpu_scaling ? 1 : 0

  name               = "${var.environment}-${local.full_service_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service_scaling_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.service_scaling_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service_scaling_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_scaling_target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "memory_scaling_policy" {
  count = var.enable_autoscaling && var.enable_memory_scaling ? 1 : 0

  name               = "${var.environment}-${local.full_service_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service_scaling_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.service_scaling_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service_scaling_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.memory_scaling_target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "request_count_scaling_policy" {
  count = var.enable_autoscaling && var.enable_request_count_scaling ? 1 : 0

  name               = "${var.environment}-${local.full_service_name}-request-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service_scaling_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.service_scaling_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service_scaling_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      # Build the resource_label from ALB ARN + target group ARN components
      resource_label = "${join("/", slice(split("/", var.alb_arn), 1, 4))}/targetgroup/${aws_lb_target_group.service_tg.name}/${split("/", aws_lb_target_group.service_tg.arn)[2]}"
    }
    target_value       = var.request_count_scaling_target
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.environment}-${local.full_service_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "${local.full_service_name} CPU utilisation above ${var.cpu_alarm_threshold}%"
  alarm_actions       = var.alarm_sns_topic_arns

  dimensions = {
    ServiceName = aws_ecs_service.service.name
    ClusterName = var.ecs_cluster_name
  }

  tags = merge(var.common_tags, {
    Name      = "${var.environment}-${local.full_service_name}-high-cpu-alarm"
    ManagedBy = "terraform"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.environment}-${local.full_service_name}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  alarm_description   = "${local.full_service_name} memory utilisation above ${var.memory_alarm_threshold}%"
  alarm_actions       = var.alarm_sns_topic_arns

  dimensions = {
    ServiceName = aws_ecs_service.service.name
    ClusterName = var.ecs_cluster_name
  }

  tags = merge(var.common_tags, {
    Name      = "${var.environment}-${local.full_service_name}-high-memory-alarm"
    ManagedBy = "terraform"
  })
}
