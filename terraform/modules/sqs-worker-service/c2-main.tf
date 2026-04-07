# =============================================================================
# sqs-worker-service module — core infrastructure
#
# Provisions a complete SQS-backed Fargate worker:
#   SQS queue + DLQ → ECR repo → ECS task def → ECS service (desired=0)
#   → App Auto Scaling (scale on queue depth) → CloudWatch alarms
#   → optional service-discovery registration
#   → optional per-service security group (falls back to caller-supplied SGs)
# =============================================================================

locals {
  full_service_name  = "${var.service_name}-service"
  root_name          = var.service_name
  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.service_sg[0].id]
}

# -----------------------------------------------------------------------------
# SQS — Main Queue
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "service_queue" {
  name = "${var.environment}-${local.full_service_name}-queue"

  delay_seconds = var.delay_seconds
  max_message_size = var.max_message_size

  # Non-prod: 1 day (fast feedback). Prod: caller-configured retention.
  # Messages that outlive retention are permanently deleted — they do NOT go to DLQ.
  message_retention_seconds = var.environment == "prod" ? var.retention_days * 86400 : 86400

  receive_wait_time_seconds  = 20 # Long polling — reduces empty-receive API costs
  visibility_timeout_seconds = var.visibility_timeout

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.service_dlq.arn
    maxReceiveCount     = var.max_retries
  })

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}-queue"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  lifecycle {
    # AWS silently caps max_message_size; ignoring prevents spurious plan diffs
    ignore_changes = [max_message_size]
  }
}

# -----------------------------------------------------------------------------
# SQS — Dead Letter Queue
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "service_dlq" {
  name = "${var.environment}-${local.full_service_name}-dlq"

  # Always 14 days — maximise investigation window for failed messages
  message_retention_seconds = 1209600

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}-dlq"
    Service     = local.root_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  lifecycle {
    ignore_changes = [max_message_size]
  }
}

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "service_repo" {
  name                 = "${var.environment}-${local.full_service_name}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = var.environment == "prod"
  }

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${local.full_service_name}"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

# Read back the latest active revision so desired_count changes by CI don't
# cause Terraform to re-register the task definition unnecessarily.
data "aws_ecs_task_definition" "service_task" {
  task_definition = aws_ecs_task_definition.service_task.family
}

resource "aws_ecs_task_definition" "service_task" {
  family                   = "${var.environment}-${local.full_service_name}-task"
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([{
    name  = "${var.environment}-${local.full_service_name}"
    image = "${aws_ecr_repository.service_repo.repository_url}:latest"

    environment = concat([
      { name = "NODE_ENV",       value = var.environment },
      { name = "SQS_QUEUE_URL", value = aws_sqs_queue.service_queue.url },
      { name = "AWS_REGION",    value = var.aws_region },
    ], var.additional_env_vars)

    environmentFiles = var.env_file_arn != "" ? [{
      value = var.env_file_arn
      type  = "s3"
    }] : []

    # Each entry needs both "name" (env var key) and "valueFrom" (secret ARN).
    # Callers should supply secrets via additional_env_vars + execution role policies
    # rather than secrets_arns when they need a specific env var name.
    secrets = [
      for arn in var.secrets_arns : { valueFrom = arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.environment}-${local.full_service_name}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "service" {
  name    = "${var.environment}-${local.full_service_name}"
  cluster = var.ecs_cluster_id

  # Pin to the higher of the Terraform-managed or externally-updated revision
  # so CI deploys (which bump the revision) don't get clobbered on next apply.
  task_definition = "${replace(aws_ecs_task_definition.service_task.arn, "/:\\d*$/", "")}:${max(aws_ecs_task_definition.service_task.revision, data.aws_ecs_task_definition.service_task.revision)}"

  desired_count = 0 # Workers start at 0 — auto-scaler drives the count
  launch_type   = "FARGATE"

  network_configuration {
    security_groups  = local.security_group_ids
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }

  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.service[0].arn
    }
  }

  lifecycle {
    # CI updates desired_count directly; ignore here to prevent plan noise
    ignore_changes = [desired_count]
  }
}

# -----------------------------------------------------------------------------
# Service Discovery (optional)
# -----------------------------------------------------------------------------

resource "aws_service_discovery_service" "service" {
  count = var.enable_service_discovery && var.service_discovery_port > 0 ? 1 : 0

  name = local.root_name

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

  tags = merge(var.common_tags, {
    Name      = "${var.environment}-${local.full_service_name}-discovery"
    ManagedBy = "terraform"
  })
}

# -----------------------------------------------------------------------------
# Security Group (created only when caller doesn't supply one)
# -----------------------------------------------------------------------------

resource "aws_security_group" "service_sg" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name_prefix = "${var.environment}-${local.full_service_name}-"
  description = "Egress-only SG for ${local.full_service_name} worker"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name      = "${var.environment}-${local.full_service_name}-sg"
    ManagedBy = "terraform"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "service_logs" {
  name              = "/ecs/${var.environment}-${local.full_service_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name      = "${var.environment}-${local.full_service_name}-logs"
    ManagedBy = "terraform"
  })
}

# -----------------------------------------------------------------------------
# App Auto Scaling
# -----------------------------------------------------------------------------

resource "aws_appautoscaling_target" "service_scaling" {
  max_capacity       = var.max_tasks
  min_capacity       = 0
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.service]
}

resource "aws_appautoscaling_policy" "scale_up" {
  name               = "${var.environment}-${local.full_service_name}-scale-up"
  service_namespace  = aws_appautoscaling_target.service_scaling.service_namespace
  resource_id        = aws_appautoscaling_target.service_scaling.resource_id
  scalable_dimension = aws_appautoscaling_target.service_scaling.scalable_dimension
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    dynamic "step_adjustment" {
      for_each = var.scale_up_steps
      content {
        metric_interval_lower_bound = step_adjustment.value.lower_bound
        metric_interval_upper_bound = lookup(step_adjustment.value, "upper_bound", null)
        scaling_adjustment          = step_adjustment.value.adjustment
      }
    }
  }
}

resource "aws_appautoscaling_policy" "scale_down" {
  name               = "${var.environment}-${local.full_service_name}-scale-down"
  service_namespace  = aws_appautoscaling_target.service_scaling.service_namespace
  resource_id        = aws_appautoscaling_target.service_scaling.resource_id
  scalable_dimension = aws_appautoscaling_target.service_scaling.scalable_dimension
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------

# Drives scale-up policy when queue has messages
resource "aws_cloudwatch_metric_alarm" "queue_depth_high" {
  alarm_name          = "${var.environment}-${local.full_service_name}-queue-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.scale_up_threshold
  alarm_description   = "Scale up ${local.full_service_name}: queue has messages"
  alarm_actions       = [aws_appautoscaling_policy.scale_up.arn]

  dimensions = { QueueName = aws_sqs_queue.service_queue.name }
}

# Drives scale-down policy when queue is empty
resource "aws_cloudwatch_metric_alarm" "queue_depth_low" {
  alarm_name          = "${var.environment}-${local.full_service_name}-queue-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 5
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Scale down ${local.full_service_name}: queue is empty"
  alarm_actions       = [aws_appautoscaling_policy.scale_down.arn]

  dimensions = { QueueName = aws_sqs_queue.service_queue.name }
}

# Pages on-call when messages pile up in the DLQ (processing failures)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.environment}-${local.full_service_name}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "${local.full_service_name} has messages in DLQ — investigate processing failures"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = { QueueName = aws_sqs_queue.service_dlq.name }
}

# Pages on-call when a message is stuck (not processed within threshold)
resource "aws_cloudwatch_metric_alarm" "queue_age_oldest" {
  alarm_name          = "${var.environment}-${local.full_service_name}-queue-age-oldest"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.queue_age_threshold_seconds
  alarm_description   = "${local.full_service_name}: oldest message age exceeds ${var.queue_age_threshold_seconds / 60} min"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = { QueueName = aws_sqs_queue.service_queue.name }

  tags = merge(var.common_tags, {
    Name      = "${var.environment}-${local.full_service_name}-queue-age-alarm"
    Metric    = "ApproximateAgeOfOldestMessage"
    Threshold = "${var.queue_age_threshold_seconds}s"
    ManagedBy = "terraform"
  })
}
