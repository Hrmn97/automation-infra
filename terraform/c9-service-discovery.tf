# =============================================================================
# Service Discovery — Shared Private DNS Namespace
#
# One namespace per environment (e.g. "dev.servefirst.local").
# Every ECS HTTP service (api, chat, auth) registers a service-discovery
# service record here so they can reach each other internally without going
# through the public ALB.
#
# This must be provisioned before any service file that references
# aws_service_discovery_private_dns_namespace.internal.id.
# =============================================================================

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "${var.environment}.servefirst.local"
  description = "Private namespace for ${var.environment} services"
  vpc         = module.api_setup.vpc_id

  tags = {
    Name        = "${var.environment}-service-discovery"
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "Service Discovery"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "service_discovery_namespace_id" {
  value       = aws_service_discovery_private_dns_namespace.internal.id
  description = "ID of the private DNS namespace — passed to each service module."
}

output "service_discovery_namespace_name" {
  value       = aws_service_discovery_private_dns_namespace.internal.name
  description = "DNS name of the private namespace (e.g. dev.servefirst.local)."
}

# Convenience endpoint strings consumed by service env-var blocks
output "api_internal_endpoint" {
  value       = "http://api.${aws_service_discovery_private_dns_namespace.internal.name}:${var.api_service_port}"
  description = "Internal API endpoint via service discovery."
}

output "chat_internal_endpoint" {
  value       = "http://chat.${aws_service_discovery_private_dns_namespace.internal.name}:${var.chat_service_port}"
  description = "Internal chat-service endpoint via service discovery."
}
