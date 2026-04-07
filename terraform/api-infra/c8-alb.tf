# ============================================================
# c8-alb.tf
# Application Load Balancer, Target Group, Listeners, ACM
# Certificate, S3 Access Logs, CloudWatch Alarms, and
# the API Performance CloudWatch Dashboard.
# ============================================================

# ------------------------------------------------------------
# Application Load Balancer
# Internet-facing ALB in public subnets. Access logs are
# shipped to S3 for audit and Athena querying.
# ------------------------------------------------------------

resource "aws_alb" "main" {
  name            = "${var.environment}-load-balancer"
  idle_timeout    = 900 # 15 min — allows long-running API calls
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.lb.id]

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb-logs"
    enabled = true
  }
}

# ------------------------------------------------------------
# Target Group — IP-mode for Fargate (no EC2 instances)
# ------------------------------------------------------------

resource "aws_alb_target_group" "app" {
  name        = "${var.environment}-target-group"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Required for awsvpc networking (Fargate)

  health_check {
    healthy_threshold   = 3
    interval            = 30
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = 5
    path                = var.health_check_path
    unhealthy_threshold = 3
  }
}

# ------------------------------------------------------------
# HTTP Listener (port 80) — permanent redirect to HTTPS
# ------------------------------------------------------------

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.main.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      host        = "#{host}"
      path        = "/#{path}"
      port        = "443"
      protocol    = "HTTPS"
      query       = "#{query}"
      status_code = "HTTP_301"
    }
  }
}

# ------------------------------------------------------------
# ACM Certificate (DNS-validated via Route 53)
# ------------------------------------------------------------

resource "aws_acm_certificate" "api_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

# Wait for Route 53 CNAME records to be created (in c10-dns.tf)
resource "aws_acm_certificate_validation" "api_cert" {
  certificate_arn         = aws_acm_certificate.api_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.api_record : record.fqdn]
}

# ------------------------------------------------------------
# HTTPS Listener (port 443) — forwards to target group
# TLS 1.2+ enforced via ELBSecurityPolicy-TLS-1-2-Ext-2018-06
# ------------------------------------------------------------

resource "aws_alb_listener" "external_alb_listener_443" {
  load_balancer_arn = aws_alb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn   = aws_acm_certificate_validation.api_cert.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.app.arn
  }
}

# ------------------------------------------------------------
# ALB CloudWatch Alarms
# ------------------------------------------------------------

# Alert when average target response time > 10 seconds
resource "aws_cloudwatch_metric_alarm" "alb_response_time_alarm" {
  alarm_name          = "${var.environment}-alb-target-response-time-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 10 # seconds
  alarm_description   = "ALB target response time exceeded 10 seconds"
  actions_enabled     = true
  alarm_actions       = [var.sns_topic]

  dimensions = {
    LoadBalancer = "app/${aws_alb.main.name}/${split("/", aws_alb.main.id)[length(split("/", aws_alb.main.id)) - 1]}"
  }
}

# Alert when 5XX errors exceed 5 per minute (3 consecutive periods)
resource "aws_cloudwatch_metric_alarm" "alb_5xx_error_alarm" {
  alarm_name          = "${var.environment}-ALB-5XX-Error-Alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "5XX errors exceeded threshold"
  alarm_actions       = [var.sns_topic]
  actions_enabled     = true

  dimensions = {
    LoadBalancer = "app/${aws_alb.main.name}/${split("/", aws_alb.main.id)[length(split("/", aws_alb.main.id)) - 1]}"
  }
}

# Alert when healthy host count drops below minimum (2 in prod, 1 elsewhere)
resource "aws_cloudwatch_metric_alarm" "alb_healthy_hosts" {
  alarm_name          = "${var.environment}-ALB-Healthy-Hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.environment == "prod" ? 2 : 1
  alarm_description   = "Number of healthy ALB targets dropped below minimum"
  alarm_actions       = [var.sns_topic]
  ok_actions          = [var.sns_topic]

  dimensions = {
    TargetGroup  = aws_alb_target_group.app.arn_suffix
    LoadBalancer = aws_alb.main.arn_suffix
  }
}

# Alert immediately when any unhealthy host is detected
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.environment}-ALB-Unhealthy-Hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 30
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Unhealthy hosts detected in ALB target group"
  alarm_actions       = [var.sns_topic]
  ok_actions          = [var.sns_topic]

  dimensions = {
    TargetGroup  = aws_alb_target_group.app.arn_suffix
    LoadBalancer = aws_alb.main.arn_suffix
  }
}

# Alert when no healthy hosts exist (service is down)
resource "aws_cloudwatch_metric_alarm" "alb_uptime" {
  alarm_name          = "${var.environment}-ALB-Uptime"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Service is down — no healthy hosts in target group"
  alarm_actions       = [var.sns_topic]
  ok_actions          = [var.sns_topic]

  dimensions = {
    TargetGroup  = aws_alb_target_group.app.arn_suffix
    LoadBalancer = aws_alb.main.arn_suffix
  }
}

# ------------------------------------------------------------
# S3 Bucket: ALB Access Logs
# Lifecycle: delete logs after 30 days. AES256 encrypted.
# ------------------------------------------------------------

resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.environment}-alb-access-logs-sf"
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "cleanup_old_logs"
    status = "Enabled"
    filter { prefix = "alb-logs/" }
    expiration { days = 30 }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# ALB service account needs PutObject permission on this bucket
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

# ------------------------------------------------------------
# S3 Bucket: Athena Query Results
# Used for querying ALB access logs via Athena.
# Auto-deleted after 30 days; AES256 encrypted.
# ------------------------------------------------------------

resource "aws_s3_bucket" "athena_results" {
  bucket = "sf-${var.environment}-athena-query-results"
}

resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "cleanup_old_results"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# ------------------------------------------------------------
# CloudWatch Dashboard: API Performance
# Provides a unified view of:
#   Row 1: Response times + Request volume
#   Row 2: Error rates (4xx/5xx) + Active connections
#   Row 3: ECS CPU, Memory, Running tasks
#   Row 4: Network in/out
#   Row 5: ALB target health
#   Row 6: Uptime % (current, daily, weekly, monthly)
#   Row 7: Application error count + slow requests (from logs)
#   Row 8: Log Insights — recent errors + slowest endpoints
# ------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "api_performance" {
  dashboard_name = "${var.environment}-api-performance"

  dashboard_body = jsonencode({
    widgets = [
      # ── Row 1: Response Time ──────────────────────────────
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "p95", "label" : "p95" }],
            [".", ".", ".", ".", { "stat" : "p50", "label" : "Median" }],
            [".", ".", ".", ".", { "stat" : "Average", "label" : "Average" }]
          ]
          period = 60, region = var.aws_region, title = "API Response Times", view = "timeSeries", stacked = false
        }
      },
      # ── Row 1: Request Volume ─────────────────────────────
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Sum" }]]
          period  = 60, region = var.aws_region, title = "Request Volume"
        }
      },
      # ── Row 2: Error Rates ────────────────────────────────
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Sum", "label" : "5XX Errors" }],
            [".", "HTTPCode_Target_4XX_Count", ".", ".", { "stat" : "Sum", "label" : "4XX Errors" }]
          ]
          period = 60, region = var.aws_region, title = "Error Rates"
        }
      },
      # ── Row 2: Active Connections ─────────────────────────
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          metrics = [["AWS/ApplicationELB", "ActiveConnectionCount", "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Sum" }]]
          period  = 60, region = var.aws_region, title = "Active Connections"
        }
      },
      # ── Row 3: ECS CPU ────────────────────────────────────
      {
        type = "metric", x = 0, y = 12, width = 8, height = 6
        properties = {
          metrics = [["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.main.name, "ClusterName", aws_ecs_cluster.main.name, { "stat" : "Average" }]]
          period  = 60, region = var.aws_region, title = "Service CPU Utilization"
        }
      },
      # ── Row 3: ECS Memory ────────────────────────────────
      {
        type = "metric", x = 8, y = 12, width = 8, height = 6
        properties = {
          metrics = [["AWS/ECS", "MemoryUtilization", "ServiceName", aws_ecs_service.main.name, "ClusterName", aws_ecs_cluster.main.name, { "stat" : "Average" }]]
          period  = 60, region = var.aws_region, title = "Service Memory Utilization"
        }
      },
      # ── Row 3: Running Tasks ──────────────────────────────
      {
        type = "metric", x = 16, y = 12, width = 8, height = 6
        properties = {
          metrics = [["ECS/ContainerInsights", "RunningTaskCount", "ServiceName", aws_ecs_service.main.name, "ClusterName", aws_ecs_cluster.main.name, { "stat" : "Average" }]]
          period  = 60, region = var.aws_region, title = "Running Tasks"
        }
      },
      # ── Row 4: Network Traffic ────────────────────────────
      {
        type = "metric", x = 0, y = 24, width = 12, height = 6
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "NetworkRxBytes", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.main.name, { "stat" : "Sum", "label" : "Network In" }],
            ["ECS/ContainerInsights", "NetworkTxBytes", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.main.name, { "stat" : "Sum", "label" : "Network Out" }]
          ]
          period = 60, region = var.aws_region, title = "Network Traffic"
        }
      },
      # ── Row 5: ALB Target Health ──────────────────────────
      {
        type = "metric", x = 0, y = 30, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_alb_target_group.app.arn_suffix, "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Average", "label" : "Healthy" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_alb_target_group.app.arn_suffix, "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Average", "label" : "Unhealthy" }]
          ]
          period = 60, region = var.aws_region, title = "ALB Target Health", view = "timeSeries", stacked = false
        }
      },
      # ── Row 6: Uptime % (5-min rolling) ──────────────────
      {
        type = "metric", x = 0, y = 36, width = 24, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_alb_target_group.app.arn_suffix, "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Average", "id" : "m1", "visible" : false }],
            [{ "expression" : "IF(m1>=1, 100, 0)", "label" : "Uptime %", "id" : "e1" }]
          ]
          period = 300, region = var.aws_region, title = "Current Uptime (Last 24 Hours)",
          view   = "timeSeries", stacked = false,
          yAxis  = { left = { min = 0, max = 100, label = "Percentage" } }
        }
      },
      # ── Row 6: Daily Uptime ───────────────────────────────
      {
        type = "metric", x = 0, y = 42, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_alb_target_group.app.arn_suffix, "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Average", "id" : "m1", "visible" : false }],
            [{ "expression" : "IF(m1>=1, 100, 0)", "label" : "Daily Uptime", "id" : "e1" }]
          ]
          period = 86400, region = var.aws_region, title = "Daily Uptime Trend (Last 30 Days)",
          view   = "timeSeries", stacked = false,
          yAxis  = { left = { min = 0, max = 100, label = "Percentage" } }
        }
      },
      # ── Row 6: Weekly Uptime ──────────────────────────────
      {
        type = "metric", x = 12, y = 42, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_alb_target_group.app.arn_suffix, "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Average", "id" : "m1", "visible" : false }],
            [{ "expression" : "IF(m1>=1, 100, 0)", "label" : "Weekly Uptime", "id" : "e1" }]
          ]
          period = 604800, region = var.aws_region, title = "Weekly Uptime Trend (Last 12 Weeks)",
          view   = "timeSeries", stacked = false,
          yAxis  = { left = { min = 0, max = 100, label = "Percentage" } }
        }
      },
      # ── Row 6: Monthly Uptime ─────────────────────────────
      {
        type = "metric", x = 0, y = 48, width = 24, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_alb_target_group.app.arn_suffix, "LoadBalancer", aws_alb.main.arn_suffix, { "stat" : "Average", "id" : "m1", "visible" : false }],
            [{ "expression" : "IF(m1>=1, 100, 0)", "label" : "Monthly Uptime", "id" : "e1" }]
          ]
          period = 2592000, region = var.aws_region, title = "Monthly Uptime Trend (Last 12 Months)",
          view   = "timeSeries", stacked = false,
          yAxis  = { left = { min = 0, max = 100, label = "Percentage" } }
        }
      },
      # ── Row 7: App Errors (from structured logs) ──────────
      {
        type = "metric", x = 0, y = 60, width = 12, height = 6
        properties = {
          metrics = [["ServeFirst/${var.environment}", "ApiErrorCount", { "stat" : "Sum", "label" : "Application Errors" }]]
          period  = 60, region = var.aws_region, title = "Application Error Rate (from logs)", view = "timeSeries"
        }
      },
      # ── Row 7: Slow Requests (>3s) ────────────────────────
      {
        type = "metric", x = 12, y = 60, width = 12, height = 6
        properties = {
          metrics = [["ServeFirst/${var.environment}", "ApiSlowRequestCount", { "stat" : "Sum", "label" : "Slow Requests (>3s)" }]]
          period  = 60, region = var.aws_region, title = "Slow Requests (>3s) — from app logs", view = "timeSeries"
        }
      },
      # ── Row 8: Log Insights — Recent Errors ───────────────
      {
        type = "log", x = 0, y = 66, width = 24, height = 6
        properties = {
          query  = "SOURCE '/api-${var.environment}' | fields @timestamp, message, service, function, error | filter level = 'error' | sort @timestamp desc | limit 20"
          region = var.aws_region, title = "Recent Application Errors", view = "table"
        }
      },
      # ── Row 8: Log Insights — Slowest Endpoints ───────────
      {
        type = "log", x = 0, y = 72, width = 24, height = 6
        properties = {
          query  = "SOURCE '/api-${var.environment}' | fields requestPath, requestMethod, responseTime | filter isSlowRequest = true | stats count() as count, avg(responseTime) as avgMs, max(responseTime) as maxMs by requestPath, requestMethod | sort count desc | limit 20"
          region = var.aws_region, title = "Slow Endpoints (>3s)", view = "table"
        }
      }
    ]
  })
}
