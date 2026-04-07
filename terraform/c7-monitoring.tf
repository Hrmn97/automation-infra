# -----------------------------------------------------------------------------
# SNS Topic for Infrastructure Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "infrastructure_alerts" {
  name = "${var.environment}-infrastructure-alerts"

  tags = {
    Name        = "${var.environment}-infrastructure-alerts"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# SNS Topic Subscriptions (Emails)
# -----------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "subscription_alan" {
  count     = var.environment == "prod" ? 1 : 0
  topic_arn = aws_sns_topic.infrastructure_alerts.arn
  protocol  = "email"
  endpoint  = "alan@servefirst.co.uk"
}

resource "aws_sns_topic_subscription" "subscription_vishal" {
  count     = var.environment == "prod" ? 1 : 0
  topic_arn = aws_sns_topic.infrastructure_alerts.arn
  protocol  = "email"
  endpoint  = "vishal@servefirst.co.uk"
}

resource "aws_sns_topic_subscription" "subscription_harman" {
  count     = var.environment == "prod" ? 1 : 0
  topic_arn = aws_sns_topic.infrastructure_alerts.arn
  protocol  = "email"
  endpoint  = "harman@servefirst.co.uk"
}
