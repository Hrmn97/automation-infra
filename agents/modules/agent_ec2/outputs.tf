output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.agent.id
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.agent.private_ip
}

output "security_group_id" {
  description = "Security group ID for the agent instance"
  value       = aws_security_group.agent.id
}

output "iam_role_name" {
  description = "IAM role name for the agent instance"
  value       = aws_iam_role.agent.name
}

output "iam_role_id" {
  description = "IAM role ID for the agent instance (for inline policy attachment)"
  value       = aws_iam_role.agent.id
}

output "iam_role_arn" {
  description = "IAM role ARN for the agent instance"
  value       = aws_iam_role.agent.arn
}

output "instance_arn" {
  description = "EC2 instance ARN"
  value       = aws_instance.agent.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.agent.name
}

output "ssm_parameter_prefix" {
  description = "SSM Parameter Store prefix for this agent's secrets"
  value       = "/openclaw/agents/${var.agent_name}"
}

output "agent_name" {
  description = "Agent name"
  value       = var.agent_name
}

output "openclaw_config" {
  description = "OpenClaw deployment configuration"
  value = {
    agent_name           = var.agent_name
    bedrock_model_ids    = var.bedrock_model_ids
    aws_region           = data.aws_region.current.name
    gateway_port         = var.gateway_port
    ssm_parameter_prefix = "/openclaw/agents/${var.agent_name}"
  }
}

output "gateway_auth_token" {
  description = "Gateway auth token for Control UI access (auto-generated if not provided)"
  value       = local.gateway_auth_token
  sensitive   = true
}
