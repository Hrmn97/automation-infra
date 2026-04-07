# ============================================================
# c6-logs.tf
# CloudWatch Log Groups, Log Streams, and Application-Level
# Metric Filters + Alarms for error and performance tracking.
# ============================================================

# ------------------------------------------------------------
# Core Log Groups
# ------------------------------------------------------------

# Main API application log group (from container → CloudWatch)
resource "aws_cloudwatch_log_group" "api_log_group" {
  name              = "/ecs/${var.environment}-app"
  retention_in_days = 30

  tags = {
    Name = "${var.environment}-api-log-group"
  }
}

# Log stream within the API log group
resource "aws_cloudwatch_log_stream" "api_log_stream" {
  name           = "ecs"
  log_group_name = aws_cloudwatch_log_group.api_log_group.name
}

# VPC Flow Logs destination (created here, referenced by c3-network.tf)
resource "aws_cloudwatch_log_group" "flowlog_log_group" {
  name              = "${var.environment}-flowlogs"
  retention_in_days = 30
}

# Cron task log group; retain longer in prod for auditing
resource "aws_cloudwatch_log_group" "crons_log_group" {
  name              = "/ecs/${var.environment}-crons"
  retention_in_days = var.environment == "prod" ? 90 : 30
}

# X-Ray daemon sidecar log group
resource "aws_cloudwatch_log_group" "xray" {
  name              = "/ecs/${var.environment}-xray"
  retention_in_days = 14

  tags = {
    Environment = var.environment
    Service     = "xray-daemon"
  }
}

# ------------------------------------------------------------
# Log Metric Filters
# Parse structured JSON logs emitted by the API container to
# extract signal counts that feed CloudWatch alarms.
# ------------------------------------------------------------

# Count every log entry where level == "error"
resource "aws_cloudwatch_log_metric_filter" "api_error_count" {
  name           = "${var.environment}-api-error-count"
  pattern        = "{ $.level = \"error\" }"
  log_group_name = "/api-${var.environment}"

  metric_transformation {
    name          = "ApiErrorCount"
    namespace     = "ServeFirst/${var.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# Count every request that the app flags as slow (>3 seconds)
resource "aws_cloudwatch_log_metric_filter" "api_slow_request_count" {
  name           = "${var.environment}-api-slow-request-count"
  pattern        = "{ $.isSlowRequest = true }"
  log_group_name = "/api-${var.environment}"

  metric_transformation {
    name          = "ApiSlowRequestCount"
    namespace     = "ServeFirst/${var.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ------------------------------------------------------------
# Application Log Alarms
# ------------------------------------------------------------

# Alert when application error count exceeds 10 per minute
resource "aws_cloudwatch_metric_alarm" "api_application_error_rate" {
  alarm_name          = "${var.environment}-api-application-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApiErrorCount"
  namespace           = "ServeFirst/${var.environment}"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 application errors in 1 minute"
  actions_enabled     = true
  alarm_actions       = [var.sns_topic]
  ok_actions          = [var.sns_topic]
  treat_missing_data  = "notBreaching"
}

# Alert when slow requests (>3 s) exceed 5 per minute
resource "aws_cloudwatch_metric_alarm" "api_slow_requests" {
  alarm_name          = "${var.environment}-api-slow-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApiSlowRequestCount"
  namespace           = "ServeFirst/${var.environment}"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "More than 5 slow requests (>3s) in 1 minute"
  actions_enabled     = true
  alarm_actions       = [var.sns_topic]
  treat_missing_data  = "notBreaching"
}
