# ============================================================
# c12-cron.tf
# ECS Cron Tasks: long-running cron service, weekly mail
# cron (prod-only), and shop metrics cron.
# All cron tasks share the same ECR image as the API.
# ============================================================

# ============================================================
# Long-Running Cron Service
# Runs continuously as an ECS service (not EventBridge-triggered).
# Handles background jobs that must run in a persistent process.
# ============================================================

# Resolve the current active revision of the long-running cron task
data "aws_ecs_task_definition" "long_running_cron_task" {
  task_definition = aws_ecs_task_definition.long_running_cron_task.family
}

locals {
  # Prod gets more resources for higher throughput; stage uses minimal resources
  fargate_long_running_cron_task_cpu    = var.environment == "prod" ? 2048 : 256
  fargate_long_running_cron_task_memory = var.environment == "prod" ? 4096 : 512
}

resource "aws_ecs_task_definition" "long_running_cron_task" {
  family                   = "${var.environment}-long-running-cron-task"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.fargate_long_running_cron_task_cpu
  memory                   = local.fargate_long_running_cron_task_memory

  container_definitions = templatefile("${path.module}/templates/ecs/cron.json.tpl", {
    image          = "${var.project_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.ecr-repo.name}:latest"
    fargate_cpu    = local.fargate_long_running_cron_task_cpu
    fargate_memory = local.fargate_long_running_cron_task_memory
    aws_region     = var.aws_region
    environment    = var.environment
    name           = "long-running-cron-task"
    jwt_secret_arn = var.JWT_secret_arn
    command        = ["node", "crons.js", "long_running_crons"]
  })
}

# ECS Service maintains exactly 1 running instance of the cron container
resource "aws_ecs_service" "cron_service" {
  count           = 1 # Always on; enable count conditional if stage resources are a concern
  name            = "${var.environment}-cron-service"
  cluster         = aws_ecs_cluster.main.id
  desired_count   = 1
  launch_type     = "FARGATE"
  task_definition = "${replace(aws_ecs_task_definition.long_running_cron_task.arn, "/:\\d*$/", "")}:${max(aws_ecs_task_definition.long_running_cron_task.revision, data.aws_ecs_task_definition.long_running_cron_task.revision)}"

  # AZ rebalancing: ECS redistributes tasks across AZs during failures
  availability_zone_rebalancing = "ENABLED"

  network_configuration {
    security_groups  = [aws_security_group.cron_service.id]
    subnets          = aws_subnet.private.*.id
    assign_public_ip = false
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_role]
}

# ============================================================
# Weekly Mail Cron (prod-only)
# Sends weekly digest emails. Triggered by EventBridge at
# 06:00 UTC every Monday.
# ============================================================

locals {
  fargate_weekl_mail_cpu     = 512
  fargate_weekly_mail_memory = 2048
}

resource "aws_ecs_task_definition" "weekly_mail_cron" {
  count                    = var.environment == "prod" ? 1 : 0
  family                   = "${var.environment}-weekly-mail-cron"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.fargate_weekl_mail_cpu
  memory                   = local.fargate_weekly_mail_memory

  container_definitions = templatefile("${path.module}/templates/ecs/cron.json.tpl", {
    image          = "${var.project_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.ecr-repo.name}:latest"
    fargate_cpu    = local.fargate_weekl_mail_cpu
    fargate_memory = local.fargate_weekly_mail_memory
    aws_region     = var.aws_region
    environment    = var.environment
    name           = "weekly-mail-cron"
    jwt_secret_arn = var.JWT_secret_arn
    command        = ["node", "crons.js", "weekly_mail"]
  })
}

# EventBridge rule: every Monday at 06:00 UTC
resource "aws_cloudwatch_event_rule" "weekly_mail_cron" {
  count               = var.environment == "prod" ? 1 : 0
  name                = "${var.environment}-weekly-mail-cron-job"
  schedule_expression = "cron(0 6 ? * 2 *)" # MON 06:00 UTC
}

resource "aws_cloudwatch_event_target" "weekly_mail_cron" {
  count     = var.environment == "prod" ? 1 : 0
  rule      = aws_cloudwatch_event_rule.weekly_mail_cron[0].name
  target_id = "${var.environment}-weekly-mail-cron-target"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge_ecs_role.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.weekly_mail_cron[0].arn
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets         = aws_subnet.private.*.id
      security_groups = var.use_shared_security_group ? [var.shared_security_group_id] : [aws_security_group.ecs_tasks.id]
    }
  }
}

# ============================================================
# Shop Metrics Cron
# Syncs shop performance metrics 4x daily.
# Staggered schedule (:15 past the hour) avoids top-of-hour
# contention with other crons hitting the database simultaneously.
# ============================================================

locals {
  fargate_shopmetrics_cpu    = var.environment == "prod" ? 2048 : 256
  fargate_shopmetrics_memory = var.environment == "prod" ? 8192 : 512
}

resource "aws_ecs_task_definition" "shopmetrics_cron" {
  family                   = "${var.environment}-shopmetrics-cron"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.fargate_shopmetrics_cpu
  memory                   = local.fargate_shopmetrics_memory

  container_definitions = templatefile("${path.module}/templates/ecs/cron.json.tpl", {
    image          = "${var.project_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.ecr-repo.name}:latest"
    fargate_cpu    = local.fargate_shopmetrics_cpu
    fargate_memory = local.fargate_shopmetrics_memory
    aws_region     = var.aws_region
    environment    = var.environment
    name           = "shopmetrics-cron"
    jwt_secret_arn = var.JWT_secret_arn
    command        = ["node", "crons.js", "sync_shop_metrics"]
  })
}

# EventBridge rule: 4x daily at :15 past 01:00, 07:00, 13:00, 19:00 UTC
resource "aws_cloudwatch_event_rule" "shopmetrics_cron" {
  name                = "${var.environment}-shopmetrics-cron-job"
  schedule_expression = "cron(15 1,7,13,19 * * ? *)"
  description         = "Sync shop metrics 4x daily, staggered to avoid DB contention"
}

resource "aws_cloudwatch_event_target" "shopmetrics_cron" {
  rule      = aws_cloudwatch_event_rule.shopmetrics_cron.name
  target_id = "${var.environment}-shopmetrics-cron-target"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge_ecs_role.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.shopmetrics_cron.arn
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets         = aws_subnet.private.*.id
      security_groups = var.use_shared_security_group ? [var.shared_security_group_id] : [aws_security_group.ecs_tasks.id]
    }
  }
}
