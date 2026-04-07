# ============================================================
# c14-outputs.tf
# Terraform outputs — used by other modules or manually when
# setting up cross-stack references (e.g., worker services).
# ============================================================

# ------------------------------------------------------------
# Networking
# ------------------------------------------------------------

output "vpc_id" {
  description = "ID of the main VPC"
  value       = aws_vpc.main.id
}

output "public_subnets" {
  description = "List of public subnet IDs (ALB, bastion)"
  value       = aws_subnet.public[*].id
}

output "private_subnets" {
  description = "List of private subnet IDs (ECS tasks, Valkey)"
  value       = aws_subnet.private[*].id
}

output "private_subnet_ids" {
  description = "Alias for private subnet IDs (backwards compatibility)"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.gw.id
}

# ------------------------------------------------------------
# Load Balancer
# ------------------------------------------------------------

output "alb_hostname" {
  description = "DNS hostname of the ALB (use alb_dns_name for clarity)"
  value       = aws_alb.main.dns_name
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_alb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_alb.main.arn
}

output "alb_listener_arn" {
  description = "ARN of the HTTPS (443) listener"
  value       = aws_alb_listener.external_alb_listener_443.arn
}

output "alb_security_group_id" {
  description = "Security group ID attached to the ALB"
  value       = aws_security_group.lb.id
}

# ------------------------------------------------------------
# ECS Cluster & Service
# ------------------------------------------------------------

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_security" {
  description = "Security group ID for ECS API tasks (short alias)"
  value       = aws_security_group.ecs_tasks.id
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS API tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "ecs_task_role_arn" {
  description = "IAM Task Role ARN used by API containers at runtime"
  value       = aws_iam_role.ecs_task_role.arn
}

output "api_service_discovery_name" {
  description = "Cloud Map DNS name for the API service (empty if service discovery is disabled)"
  value       = var.enable_service_discovery ? "api.${var.service_discovery_namespace_id}" : ""
}

# ------------------------------------------------------------
# Valkey (ElastiCache)
# ------------------------------------------------------------

output "valkey_endpoint" {
  description = "Primary endpoint DNS name for the Valkey cluster"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "valkey_port" {
  description = "Port number the Valkey cluster listens on"
  value       = var.valkey_port
}
