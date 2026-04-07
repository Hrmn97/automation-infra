# ============================================================
# c11-valkey.tf
# ElastiCache Valkey (Redis-compatible) — Security Groups,
# Subnet Group, Parameter Group, Replication Group, and
# CloudWatch Alarms
# ============================================================

# ------------------------------------------------------------
# Valkey Security Group
# Restricts access to Valkey port (6379) from:
#   - API ECS tasks (legacy, always open)
#   - Shared ECS security group (optional, cross-service)
#   - Bastion host (for developer tunneling)
# ------------------------------------------------------------

resource "aws_security_group" "valkey" {
  name        = "${var.environment}-valkey-sg"
  description = "Security group for Valkey ElastiCache"
  vpc_id      = aws_vpc.main.id

  # API service (primary consumer of Valkey)
  ingress {
    from_port       = var.valkey_port
    to_port         = var.valkey_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
    description     = "Valkey traffic from API ECS tasks"
  }

  # Optional: shared SG for other ECS services (e.g., background workers)
  dynamic "ingress" {
    for_each = var.use_shared_security_group ? [1] : []
    content {
      from_port       = var.valkey_port
      to_port         = var.valkey_port
      protocol        = "tcp"
      security_groups = [var.shared_security_group_id]
      description     = "Valkey traffic from shared ECS services"
    }
  }

  # Bastion host access for developer debugging via SSH tunnel
  ingress {
    from_port       = var.valkey_port
    to_port         = var.valkey_port
    protocol        = "tcp"
    security_groups = [aws_security_group.allow-ssh.id]
    description     = "Valkey access from bastion host"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-valkey-sg"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# Developer Access Security Group
# Terraform creates the SG shell but ignores all rule changes.
# Developers add/remove their own IP rules via console or CLI.
# ------------------------------------------------------------

resource "aws_security_group" "valkey_developer_access" {
  name        = "${var.environment}-valkey-developer-access"
  description = "Developer access to Valkey — rules managed manually"
  vpc_id      = aws_vpc.main.id

  # No rules defined here — added manually by developers
  tags = {
    Name        = "${var.environment}-valkey-developer-access"
    Environment = var.environment
    Note        = "Add developer IPs manually — Terraform ignores rule changes"
  }

  lifecycle {
    ignore_changes = [ingress, egress] # Prevent Terraform from removing manual IPs
  }
}

# ------------------------------------------------------------
# Valkey Subnet Group — places the cluster in private subnets
# ------------------------------------------------------------

resource "aws_elasticache_subnet_group" "valkey" {
  name       = "${var.environment}-valkey-subnet-group"
  subnet_ids = aws_subnet.private.*.id
}

# ------------------------------------------------------------
# Valkey Parameter Group
# allkeys-lru: evict least-recently-used keys when memory full
# Suitable for a caching use-case where stale data is acceptable
# ------------------------------------------------------------

resource "aws_elasticache_parameter_group" "valkey" {
  name   = "${var.environment}-valkey-params"
  family = "valkey8"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}

# ------------------------------------------------------------
# Valkey Replication Group
# Single-node (num_cache_clusters = 1, no automatic failover).
# Bump to multi-node in prod if HA is required.
# Backups: 7-day retention in prod, 1-day in stage.
# ------------------------------------------------------------

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = "${var.environment}-valkey"
  description          = "${var.environment} Valkey cluster"
  engine               = "valkey"
  engine_version       = "8.0"
  node_type            = var.valkey_node_type
  parameter_group_name = aws_elasticache_parameter_group.valkey.name
  subnet_group_name    = aws_elasticache_subnet_group.valkey.name

  security_group_ids = [
    aws_security_group.valkey.id,
    aws_security_group.valkey_developer_access.id,
  ]

  port               = var.valkey_port
  apply_immediately  = true
  maintenance_window = var.valkey_maintenance_window

  # Single-node — no replicas, no automatic failover
  num_cache_clusters         = 1
  automatic_failover_enabled = false

  snapshot_retention_limit = var.environment == "prod" ? 7 : 1
  snapshot_window          = var.valkey_snapshot_window
}

# ------------------------------------------------------------
# Valkey CloudWatch Alarms
# ------------------------------------------------------------

# CPU utilization exceeded configured threshold
resource "aws_cloudwatch_metric_alarm" "valkey_cpu" {
  alarm_name          = "${var.environment}-valkey-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 120
  statistic           = "Average"
  threshold           = var.valkey_cpu_alarm_threshold
  alarm_description   = "Valkey CPU utilization exceeded threshold"
  alarm_actions       = [var.sns_topic]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.valkey.id
  }
}

# Memory usage exceeded configured threshold
resource "aws_cloudwatch_metric_alarm" "valkey_memory" {
  alarm_name          = "${var.environment}-valkey-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 120
  statistic           = "Average"
  threshold           = var.valkey_memory_alarm_threshold
  alarm_description   = "Valkey memory usage exceeded threshold"
  alarm_actions       = [var.sns_topic]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.valkey.id
  }
}

# Concurrent connection count too high (risk of connection exhaustion)
resource "aws_cloudwatch_metric_alarm" "valkey_connections" {
  alarm_name          = "${var.environment}-valkey-current-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CurrConnections"
  namespace           = "AWS/ElastiCache"
  period              = 120
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "Valkey concurrent connections exceeded 100"
  alarm_actions       = [var.sns_topic]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.valkey.id
  }
}

# Freeable memory dropped below 100 MB (risk of OOM evictions)
resource "aws_cloudwatch_metric_alarm" "valkey_freeable_memory" {
  alarm_name          = "${var.environment}-valkey-freeable-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeableMemory"
  namespace           = "AWS/ElastiCache"
  period              = 120
  statistic           = "Average"
  threshold           = 100000000 # 100 MB
  alarm_description   = "Valkey freeable memory dropped below 100 MB"
  alarm_actions       = [var.sns_topic]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.valkey.id
  }
}
