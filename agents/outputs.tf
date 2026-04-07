output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.network.public_subnet_ids
}

output "nat_gateway_ips" {
  description = "Elastic IPs of NAT Gateways"
  value       = module.network.nat_gateway_ips
}

output "vpc_endpoints" {
  description = "Map of VPC endpoint IDs"
  value       = module.network.vpc_endpoints
}

output "agent_instances" {
  description = "Map of agent instance details"
  value = {
    for name, agent in module.agents : name => {
      instance_id          = agent.instance_id
      private_ip           = agent.private_ip
      security_group_id    = agent.security_group_id
      iam_role_name        = agent.iam_role_name
      iam_role_arn         = agent.iam_role_arn
      log_group_name       = agent.log_group_name
      ssm_parameter_prefix = agent.ssm_parameter_prefix
      openclaw_config      = agent.openclaw_config
    }
  }
}

output "ssm_connection_commands" {
  description = "Commands to connect to each agent via SSM Session Manager"
  value = {
    for name, agent in module.agents : name => "aws ssm start-session --target ${agent.instance_id} --region ${var.aws_region}"
  }
}

output "cloudwatch_log_commands" {
  description = "Commands to tail CloudWatch logs for each agent"
  value = {
    for name, agent in module.agents : name => "aws logs tail ${agent.log_group_name} --follow --region ${var.aws_region}"
  }
}

output "network_security_summary" {
  description = "Security summary of the network configuration"
  value = {
    vpc_cidr             = var.vpc_cidr
    nat_enabled          = var.enable_nat_gateway && !var.break_glass_mode
    break_glass_mode     = var.break_glass_mode
    vpc_endpoints_count  = length(module.network.vpc_endpoints)
    internet_access      = var.break_glass_mode ? "DISABLED (Air-gapped)" : (var.enable_nat_gateway ? "Via NAT Gateway" : "DISABLED")
  }
}

output "agent_summary" {
  description = "Summary of deployed agents"
  value = {
    total_agents = length(module.agents)
    agent_names  = keys(module.agents)
    by_instance_type = {
      for name, config in var.agents : config.instance_type => name...
    }
  }
}

# Sensitive outputs (use terraform output -json to retrieve)
output "kms_key_id" {
  description = "KMS key ID for CloudWatch Logs encryption"
  value       = module.network.kms_key_id
  sensitive   = true
}

output "gateway_auth_tokens" {
  description = "Gateway auth tokens for each agent's Control UI (use: terraform output -json gateway_auth_tokens)"
  value = {
    for name, agent in module.agents : name => agent.gateway_auth_token
  }
  sensitive = true
}

output "ssm_port_forward_commands" {
  description = "Commands to port-forward to each agent's OpenClaw dashboard"
  value = {
    for name, agent in module.agents : name => "aws ssm start-session --target ${agent.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${agent.openclaw_config.gateway_port}\"],\"localPortNumber\":[\"${agent.openclaw_config.gateway_port}\"]}' --region ${var.aws_region}"
  }
}
