# ============================================================
# c9-autoscaling.tf
# ECS Auto Scaling: scale up/down based on CPU utilization.
# Max capacity is 6 in prod, 1 in all other environments.
# ============================================================

# ------------------------------------------------------------
# Scalable Target — registers the ECS service with
# Application Auto Scaling so policies can be applied.
# ------------------------------------------------------------

resource "aws_appautoscaling_target" "target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.api_desired_instances_count
  max_capacity       = var.environment == "prod" ? 6 : 1
}

# ------------------------------------------------------------
# Scale-Up Policy
# Adds 1 task when the scale-up alarm fires.
# Cooldown of 60 seconds prevents rapid successive scale-ups.
# ------------------------------------------------------------

resource "aws_appautoscaling_policy" "up" {
  name               = "${var.environment}-api_scale_up"
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }

  depends_on = [aws_appautoscaling_target.target]
}

# ------------------------------------------------------------
# Scale-Down Policy
# Removes 1 task when the scale-down alarm fires.
# Two evaluation periods required before scaling down to
# avoid flapping.
# ------------------------------------------------------------

resource "aws_appautoscaling_policy" "down" {
  name               = "${var.environment}-api_scale_down"
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }

  depends_on = [aws_appautoscaling_target.target]
}

# ------------------------------------------------------------
# CloudWatch Alarm: CPU High → triggers scale-up
# Fires after 1 period (60 s) at ≥70% CPU
# ------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  alarm_name          = "${var.environment}-api_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = [aws_appautoscaling_policy.up.arn]
}

# ------------------------------------------------------------
# CloudWatch Alarm: CPU Low → triggers scale-down
# Fires after 2 periods at ≤10% CPU (prevents flapping)
# ------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "service_cpu_low" {
  alarm_name          = "${var.environment}-api_cpu_utilization_low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 10

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = [aws_appautoscaling_policy.down.arn]
}
