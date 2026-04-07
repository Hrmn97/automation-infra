# ============================================================
# c3-network.tf
# VPC, Subnets, Internet Gateway, NAT Gateway, and Flow Logs
# ============================================================

# ------------------------------------------------------------
# Availability Zones
# ------------------------------------------------------------

# Fetch all available AZs in the configured region
data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------
# VPC
# ------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-sfv2"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# Private Subnets (one per AZ — for ECS tasks, Valkey, etc.)
# ------------------------------------------------------------

resource "aws_subnet" "private" {
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-privatesub-${count.index}-sfv2"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# Public Subnets (one per AZ — for ALB and bastion)
# Offset by az_count to avoid CIDR overlap with private subnets
# ------------------------------------------------------------

resource "aws_subnet" "public" {
  count                   = var.az_count
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = aws_vpc.main.id
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-pubsub-${count.index}-sfv2"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# Internet Gateway (IGW) — provides public internet access
# ------------------------------------------------------------

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-igw-sfv2"
    Environment = var.environment
  }
}

# Route all traffic from public subnets through the IGW
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# ------------------------------------------------------------
# NAT Gateway — allows private subnets to reach the internet
# (outbound only; ECS tasks pull images, make API calls, etc.)
# ------------------------------------------------------------

# Elastic IP for the NAT Gateway
resource "aws_eip" "gw" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.gw]

  tags = {
    Name        = "${var.environment}-eip-sfv2"
    Environment = var.environment
  }
}

# NAT Gateway lives in the first public subnet
resource "aws_nat_gateway" "gw" {
  subnet_id     = aws_subnet.public[0].id
  allocation_id = aws_eip.gw.id

  tags = {
    Name        = "${var.environment}-nat-sfv2"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# VPC Flow Logs — capture all traffic metadata for auditing
# ------------------------------------------------------------

resource "aws_flow_log" "aws_flowlog" {
  depends_on      = [aws_vpc.main]
  iam_role_arn    = aws_iam_role.flowlogs_role.arn
  log_destination = aws_cloudwatch_log_group.flowlog_log_group.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

output "flowlog_arn" {
  description = "ARN of the VPC Flow Log"
  value       = aws_flow_log.aws_flowlog.arn
}
