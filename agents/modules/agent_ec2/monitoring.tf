# CloudWatch Dashboard and Alarms for agent host monitoring
# Only created when enable_host_metrics = true

resource "aws_cloudwatch_dashboard" "agent_host" {
  count          = var.enable_host_metrics ? 1 : 0
  dashboard_name = "${local.agent_full_name}-host"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "CPU Utilization"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.agent.id, { stat = "Average", period = 300 }],
            [var.host_metrics_namespace, "cpu_usage_user", "InstanceId", aws_instance.agent.id, "cpu", "cpu-total", "InstanceType", var.instance_type, { stat = "Average", period = 300 }],
            [var.host_metrics_namespace, "cpu_usage_system", "InstanceId", aws_instance.agent.id, "cpu", "cpu-total", "InstanceType", var.instance_type, { stat = "Average", period = 300 }],
          ]
          view    = "timeSeries"
          stacked = false
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Memory Usage (%)"
          region = data.aws_region.current.name
          metrics = [
            [var.host_metrics_namespace, "mem_used_percent", "InstanceId", aws_instance.agent.id, "InstanceType", var.instance_type, { stat = "Average", period = 300, color = "#d62728" }],
          ]
          view    = "timeSeries"
          stacked = false
          yAxis   = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ label = "Alarm threshold", value = 85, color = "#ff0000" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Disk Usage (%)"
          region = data.aws_region.current.name
          metrics = [
            [var.host_metrics_namespace, "disk_used_percent", "InstanceId", aws_instance.agent.id, "InstanceType", var.instance_type, "path", "/", "device", "nvme0n1p1", "fstype", "xfs", { stat = "Average", period = 300, color = "#ff7f0e" }],
          ]
          view    = "timeSeries"
          stacked = false
          yAxis   = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [
              { label = "Warning", value = 80, color = "#ffcc00" },
              { label = "Critical", value = 90, color = "#ff0000" },
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Network Traffic"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.agent.id, { stat = "Average", period = 300, label = "In" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.agent.id, { stat = "Average", period = 300, label = "Out" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "Memory (bytes)"
          region = data.aws_region.current.name
          metrics = [
            [var.host_metrics_namespace, "mem_used", "InstanceId", aws_instance.agent.id, "InstanceType", var.instance_type, { stat = "Average", period = 300, label = "Used" }],
            [var.host_metrics_namespace, "mem_available", "InstanceId", aws_instance.agent.id, "InstanceType", var.instance_type, { stat = "Average", period = 300, label = "Available" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "Disk Space (bytes)"
          region = data.aws_region.current.name
          metrics = [
            [var.host_metrics_namespace, "disk_used", "InstanceId", aws_instance.agent.id, "InstanceType", var.instance_type, "path", "/", "device", "nvme0n1p1", "fstype", "xfs", { stat = "Average", period = 300, label = "Used" }],
            [var.host_metrics_namespace, "disk_free", "InstanceId", aws_instance.agent.id, "InstanceType", var.instance_type, "path", "/", "device", "nvme0n1p1", "fstype", "xfs", { stat = "Average", period = 300, label = "Free" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "EBS I/O"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/EC2", "EBSReadOps", "InstanceId", aws_instance.agent.id, { stat = "Sum", period = 300, label = "Read Ops" }],
            ["AWS/EC2", "EBSWriteOps", "InstanceId", aws_instance.agent.id, { stat = "Sum", period = 300, label = "Write Ops" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "text"
        x      = 0
        y      = 18
        width  = 24
        height = 2
        properties = {
          markdown = "## Instance: ${aws_instance.agent.id} | Type: ${var.instance_type} | Volume: ${var.root_volume_size_gb}GB | Region: ${data.aws_region.current.name}\n**Metrics namespace:** `${var.host_metrics_namespace}` | **Collection interval:** ${var.host_metrics_interval}s"
        }
      },
    ]
  })
}

# Alarm: High memory usage
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count               = var.enable_host_metrics ? 1 : 0
  alarm_name          = "${local.agent_full_name}-memory-high"
  alarm_description   = "Memory usage above 85% for 10 minutes on ${var.agent_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = var.host_metrics_namespace
  period              = 300
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId   = aws_instance.agent.id
    InstanceType = var.instance_type
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.tags, {
    Agent = var.agent_name
  })
}

# Alarm: Disk usage warning (80%)
resource "aws_cloudwatch_metric_alarm" "disk_warning" {
  count               = var.enable_host_metrics ? 1 : 0
  alarm_name          = "${local.agent_full_name}-disk-warning"
  alarm_description   = "Disk usage above 80% on ${var.agent_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = var.host_metrics_namespace
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId   = aws_instance.agent.id
    InstanceType = var.instance_type
    path         = "/"
    device       = "nvme0n1p1"
    fstype       = "xfs"
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.tags, {
    Agent = var.agent_name
  })
}

# Alarm: Disk usage critical (90%)
resource "aws_cloudwatch_metric_alarm" "disk_critical" {
  count               = var.enable_host_metrics ? 1 : 0
  alarm_name          = "${local.agent_full_name}-disk-critical"
  alarm_description   = "CRITICAL: Disk usage above 90% on ${var.agent_name} — immediate action required"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = var.host_metrics_namespace
  period              = 300
  statistic           = "Average"
  threshold           = 90
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId   = aws_instance.agent.id
    InstanceType = var.instance_type
    path         = "/"
    device       = "nvme0n1p1"
    fstype       = "xfs"
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.tags, {
    Agent = var.agent_name
  })
}

# Alarm: High CPU sustained
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.enable_host_metrics ? 1 : 0
  alarm_name          = "${local.agent_full_name}-cpu-high"
  alarm_description   = "CPU usage above 90% for 15 minutes on ${var.agent_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = aws_instance.agent.id
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.tags, {
    Agent = var.agent_name
  })
}
