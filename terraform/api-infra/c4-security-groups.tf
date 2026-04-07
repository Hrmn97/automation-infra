# ============================================================
# c4-security.tf
# Security Groups: ALB, ECS Tasks, Cron Service, SSH Bastion
# ============================================================

# ------------------------------------------------------------
# Ingress Rules Variable
# Defines which ports are open to the public on the ALB.
# Currently only HTTP (redirect) and HTTPS are allowed.
# ------------------------------------------------------------

variable "ingress_rules" {
  description = "List of ingress rules applied to the ALB security group"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_block  = string
    description = string
  }))
  default = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_block  = "0.0.0.0/0"
      description = "HTTPS from internet"
    },
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_block  = "0.0.0.0/0"
      description = "HTTP from internet (redirected to HTTPS by listener)"
    }
  ]
}

# ------------------------------------------------------------
# ALB Security Group
# Controls inbound traffic to the Application Load Balancer.
# Outbound is fully open (ALB forwards to ECS tasks).
# ------------------------------------------------------------

resource "aws_security_group" "lb" {
  name        = "${var.environment}-load-balancer-security-group"
  description = "Controls access to the ALB"
  vpc_id      = aws_vpc.main.id

  # Egress: allow ALB to forward requests to ECS
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Ingress rules are applied dynamically via the variable above
resource "aws_security_group_rule" "ingress_rules" {
  count = length(var.ingress_rules)

  type              = "ingress"
  from_port         = var.ingress_rules[count.index].from_port
  to_port           = var.ingress_rules[count.index].to_port
  protocol          = var.ingress_rules[count.index].protocol
  cidr_blocks       = [var.ingress_rules[count.index].cidr_block]
  description       = var.ingress_rules[count.index].description
  security_group_id = aws_security_group.lb.id
}

# ------------------------------------------------------------
# ECS API Tasks Security Group
# API-specific SG. Only the ALB can send traffic on app_port.
# Optionally allows shared ECS services (cross-service comms).
# ------------------------------------------------------------

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.environment}-ecs-tasks-security-group"
  description = "Allows inbound access from the ALB only (API-specific)"
  vpc_id      = aws_vpc.main.id

  # Only the ALB can reach the API on app_port
  ingress {
    protocol        = "tcp"
    from_port       = var.app_port
    to_port         = var.app_port
    security_groups = [aws_security_group.lb.id]
    description     = "API traffic from ALB"
  }

  # Self-referencing rule for service discovery / task-to-task
  ingress {
    protocol    = "tcp"
    from_port   = 0
    to_port     = 65535
    self        = true
    description = "Internal service-discovery communication"
  }

  # Optional: allow traffic from the shared ECS SG (e.g., worker services)
  dynamic "ingress" {
    for_each = var.enable_shared_security_group ? [1] : []
    content {
      protocol        = "tcp"
      from_port       = var.app_port
      to_port         = var.app_port
      security_groups = [var.shared_security_group_id]
      description     = "Allow from shared ECS services (cross-service comms)"
    }
  }

  # SSH from bastion only
  ingress {
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.allow-ssh.id]
    description     = "SSH access from bastion"
  }

  # Egress: fully open (ECS tasks need internet for ECR, Secrets Manager, etc.)
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------
# Cron Service Security Group
# No inbound access required — cron tasks initiate all traffic.
# ------------------------------------------------------------

resource "aws_security_group" "cron_service" {
  name        = "${var.environment}-cron-service-security-group"
  description = "No inbound access — cron tasks are outbound-only"
  vpc_id      = aws_vpc.main.id

  # Egress: fully open (needs to call internal APIs and AWS services)
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------
# SSH Bastion Security Group
# Allows SSH (port 22) from anywhere — restrict CIDR in prod.
# ------------------------------------------------------------

resource "aws_security_group" "allow-ssh" {
  name        = "allow-ssh"
  description = "Allows SSH access to bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Tighten to known IPs in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-allow-open-ssh"
  }
}

# ------------------------------------------------------------
# [Decommissioned] MongoDB Security Group
# Kept commented for reference — Mongo is no longer in VPC.
# ------------------------------------------------------------

# resource "aws_security_group" "mongo" { ... }
