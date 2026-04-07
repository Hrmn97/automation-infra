# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  agent_full_name = "${var.project_name}-${var.environment}-${var.agent_name}"

  # Bedrock model ARN construction
  # Supports both foundation models and cross-region inference profiles
  # Inference profile IDs start with a region prefix (us., eu., ap., global.)
  # Cross-region inference profiles need BOTH the inference-profile ARN
  # AND the underlying foundation-model ARN (for the region they route to)
  bedrock_inference_profile_arns = [
    for id in var.bedrock_model_ids :
    "arn:aws:bedrock:*:*:inference-profile/${id}"
    if can(regex("^(us|eu|ap|global)\\.", id))
  ]

  bedrock_foundation_model_arns = [
    for id in var.bedrock_model_ids :
    "arn:aws:bedrock:*::foundation-model/${id}"
    if !can(regex("^(us|eu|ap|global)\\.", id)) && !can(regex("^arn:aws:", id))
  ]

  # Extract foundation model IDs from cross-region inference profiles
  # e.g., "eu.anthropic.claude-opus-4-6-v1" -> "anthropic.claude-opus-4-6-v1"
  bedrock_cross_region_foundation_arns = [
    for id in var.bedrock_model_ids :
    "arn:aws:bedrock:*::foundation-model/${regex("^(?:us|eu|ap|global)\\.(.*)", id)[0]}"
    if can(regex("^(us|eu|ap|global)\\.", id))
  ]

  bedrock_explicit_arns = [
    for id in var.bedrock_model_ids :
    id
    if can(regex("^arn:aws:", id))
  ]

  bedrock_model_arns = distinct(concat(
    local.bedrock_inference_profile_arns,
    local.bedrock_foundation_model_arns,
    local.bedrock_cross_region_foundation_arns,
    local.bedrock_explicit_arns,
  ))

  # Gateway auth token: use provided value or auto-generate
  gateway_auth_token = var.gateway_auth_token != "" ? var.gateway_auth_token : random_password.gateway_token[0].result
}

# Auto-generate gateway auth token if not provided
resource "random_password" "gateway_token" {
  count   = var.gateway_auth_token == "" ? 1 : 0
  length  = 48
  special = false # Alphanumeric only for JSON safety
}

# Security Group for agent instance
resource "aws_security_group" "agent" {
  name_prefix = "${local.agent_full_name}-"
  description = "Security group for OpenClaw agent: ${var.agent_name}"
  vpc_id      = var.vpc_id

  # ZERO inbound - access via SSM Session Manager only
  # Egress rules below

  tags = merge(
    var.tags,
    {
      Name  = "${local.agent_full_name}-sg"
      Agent = var.agent_name
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Egress - HTTPS only (for VPC endpoints, NAT, and Bedrock)
resource "aws_security_group_rule" "https_egress" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS for AWS API calls, VPC endpoints, and Bedrock"
  security_group_id = aws_security_group.agent.id
}

# Egress - HTTP for package installation (can be removed if using pre-baked AMI)
resource "aws_security_group_rule" "http_egress" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP for package repositories (yum/dnf)"
  security_group_id = aws_security_group.agent.id
}

# Custom security group rules (if provided)
resource "aws_security_group_rule" "custom" {
  for_each = { for idx, rule in var.custom_security_group_rules : idx => rule }

  type              = each.value.type
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
  description       = each.value.description
  security_group_id = aws_security_group.agent.id
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "agent" {
  name              = "/openclaw/agent/${var.agent_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name  = "${local.agent_full_name}-logs"
      Agent = var.agent_name
    }
  )
}

# EC2 Instance
resource "aws_instance" "agent" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.agent.id]
  iam_instance_profile   = aws_iam_instance_profile.agent.name

  # IMDSv2 required (prevents SSRF attacks)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2 # Required for Docker containers to reach IMDS
    instance_metadata_tags      = "enabled"
  }

  # Encrypted root volume (gp3 for better performance/cost)
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = false
    iops                  = 3000  # gp3 default
    throughput            = 125   # gp3 default (MB/s)

    tags = merge(
      var.tags,
      {
        Name  = "${local.agent_full_name}-root"
        Agent = var.agent_name
      }
    )
  }

  monitoring = var.detailed_monitoring

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    agent_name           = var.agent_name
    aws_region           = data.aws_region.current.name
    cloudwatch_log_group = aws_cloudwatch_log_group.agent.name
    bedrock_model_id     = var.bedrock_model_ids[0]
    gateway_port         = var.gateway_port
    telegram_bot_token   = var.telegram_bot_token
    gateway_auth_token   = local.gateway_auth_token
    enable_host_metrics  = var.enable_host_metrics
    host_metrics_namespace = var.host_metrics_namespace
    host_metrics_interval  = var.host_metrics_interval
  }))

  user_data_replace_on_change = false

  tags = merge(
    var.tags,
    {
      Name  = local.agent_full_name
      Agent = var.agent_name
    }
  )

  lifecycle {
    ignore_changes = [
      ami,       # Prevent replacement when new AMI available
      user_data, # Config changes are applied directly on the instance, not via replacement
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
    aws_cloudwatch_log_group.agent
  ]
}
