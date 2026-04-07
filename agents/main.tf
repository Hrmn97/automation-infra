# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local variables
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  )
}

# Network foundation
module "network" {
  source = "./modules/network"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  enable_nat_gateway   = var.enable_nat_gateway
  nat_gateway_per_az   = var.enable_nat_gateway_per_az
  break_glass_mode     = var.break_glass_mode
  enable_vpc_flow_logs = var.enable_vpc_flow_logs
  enable_kms_encryption = var.enable_kms_encryption
  cloudwatch_log_retention_days = var.cloudwatch_log_retention_days
  additional_vpc_endpoint_services = var.additional_vpc_endpoint_services

  tags = local.common_tags
}

# Agent instances
module "agents" {
  source = "./modules/agent_ec2"

  for_each = var.agents

  # Agent identification
  agent_name   = each.key
  environment  = var.environment
  project_name = var.project_name

  # Network configuration
  vpc_id            = module.network.vpc_id
  private_subnet_id = module.network.private_subnet_ids[each.value.subnet_index]
  vpc_endpoint_sg_id = module.network.vpc_endpoint_security_group_id

  # Instance configuration
  instance_type       = each.value.instance_type
  root_volume_size_gb = each.value.root_volume_size_gb
  detailed_monitoring = each.value.detailed_monitoring

  # OpenClaw configuration
  openclaw_version    = coalesce(each.value.openclaw_version, var.openclaw_default_version)
  bedrock_model_ids   = each.value.bedrock_model_ids
  enable_marketplace  = each.value.enable_marketplace
  allowed_bedrock_regions = var.allowed_bedrock_regions

  # Gateway & channels
  gateway_port       = each.value.gateway_port
  telegram_bot_token = var.telegram_bot_token
  gateway_auth_token = var.gateway_auth_token

  # Logging
  cloudwatch_log_retention_days = var.cloudwatch_log_retention_days
  kms_key_id                    = var.enable_kms_encryption ? module.network.kms_key_id : null

  # Security
  enable_self_diagnostics     = each.value.enable_self_diagnostics
  enable_host_metrics         = each.value.enable_host_metrics
  custom_security_group_rules = each.value.custom_security_group_rules
  additional_iam_policies     = each.value.additional_iam_policies

  # EBS Snapshots
  enable_ebs_snapshots   = each.value.enable_ebs_snapshots
  snapshot_hourly_retain = each.value.snapshot_hourly_retain
  snapshot_daily_retain  = each.value.snapshot_daily_retain

  # Tags
  tags = local.common_tags

  depends_on = [
    module.network
  ]
}
