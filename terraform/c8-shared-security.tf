# =============================================================================
# Shared Security Group for all ECS Tasks
#
# This single security group is reused by every ECS service (api, chat, auth,
# pdf, workflow, syncreviews, response).  Keeping it here — at the root module
# level — avoids duplication across individual service files and makes ingress
# rule management a single-touch operation.
# =============================================================================

# -----------------------------------------------------------------------------
# Locals — build the ingress port list from typed service-port variables
# Defined here rather than in c3 to keep security group concerns co-located.
# -----------------------------------------------------------------------------
locals {
  # Each entry drives one dynamic ingress block on the shared SG below.
  # Add new services here — no other file needs to change.
  ecs_ingress_ports = [
    {
      port        = var.api_service_port
      description = "Main API service"
    },
    {
      port        = var.chat_service_port
      description = "Chat service"
    },
    {
      port        = var.auth_service_port
      description = "Auth service"
    },
  ]
}

# -----------------------------------------------------------------------------
# Shared ECS Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "ecs_shared_tasks" {
  name        = "${var.environment}-ecs-shared-tasks-sg"
  description = "Shared security group for all ECS tasks in ${var.environment}"
  vpc_id      = module.api_setup.vpc_id

  # ── ALB → container ingress (one rule per registered service port) ──────────
  dynamic "ingress" {
    for_each = local.ecs_ingress_ports

    content {
      protocol        = "tcp"
      from_port       = ingress.value.port
      to_port         = ingress.value.port
      security_groups = [module.api_setup.alb_security_group_id]
      description     = ingress.value.description
    }
  }

  # ── Service-to-service (self) ingress via Cloud Map / service discovery ─────
  ingress {
    protocol    = "tcp"
    from_port   = 0
    to_port     = 65535
    self        = true
    description = "Internal ECS task-to-task communication (service discovery)"
  }

  # ── Unrestricted egress — tasks need to reach ECR, S3, Secrets Manager, etc.
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.environment}-ecs-shared-tasks-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "Shared ECS task security group"
  }
}

# -----------------------------------------------------------------------------
# Output — consumed by all service modules via root module references
# -----------------------------------------------------------------------------
output "ecs_shared_tasks_security_group_id" {
  description = "Security group ID used by all shared ECS tasks"
  value       = aws_security_group.ecs_shared_tasks.id
}
