# ---------------------------------------------------------------------------
# MongoDB Atlas VPC Peering
#
# Establishes a private network tunnel between the AWS VPC and MongoDB Atlas
# so application traffic never traverses the public internet.
#
# Flow:
#   1. Atlas side  — mongodbatlas_network_peering    : initiates the peering request
#   2. Atlas side  — mongodbatlas_project_ip_access_list : whitelists the VPC CIDR in Atlas
#   3. AWS side    — aws_vpc_peering_connection_accepter  : accepts the peering request
#   4. AWS side    — aws_route_table                      : routes Atlas-bound traffic over the peer
#   5. AWS side    — aws_route_table_association          : attaches the route table to private subnets
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# 1. Atlas — initiate VPC peering request
# ---------------------------------------------------------------------------

resource "mongodbatlas_network_peering" "atlas_network_peering" {
  project_id             = var.ATLAS_PROJECT_ID
  container_id           = mongodbatlas_cluster.cluster-vpc-peer.container_id
  provider_name          = var.ATLAS_PROVIDER
  accepter_region_name   = var.aws_region
  vpc_id                 = module.api_setup.vpc_id
  aws_account_id         = var.project_id
  route_table_cidr_block = var.vpc_cidr
}

# ---------------------------------------------------------------------------
# 2. Atlas — whitelist the AWS VPC CIDR in the Atlas IP access list
#    (Peering alone is not enough; Atlas also requires an explicit allowlist entry)
# ---------------------------------------------------------------------------

resource "mongodbatlas_project_ip_access_list" "atlas_ip_access_list" {
  project_id = var.ATLAS_PROJECT_ID
  cidr_block = var.vpc_cidr
  comment    = "${var.environment} AWS VPC CIDR — private Atlas access"
}

# ---------------------------------------------------------------------------
# 3. AWS — accept the peering connection initiated by Atlas
#    auto_accept = true lets Terraform handle the handshake automatically.
#    DNS resolution is enabled so Atlas connection strings resolve privately.
# ---------------------------------------------------------------------------

resource "aws_vpc_peering_connection_accepter" "peer" {
  vpc_peering_connection_id = mongodbatlas_network_peering.atlas_network_peering.connection_id
  auto_accept               = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-atlas-vpc-peer"
  })
}

# ---------------------------------------------------------------------------
# 4. AWS — route table for private subnets
#    Two routes:
#      - Atlas CIDR  → peering connection (private tunnel to MongoDB)
#      - All others  → NAT gateway (general internet egress)
# ---------------------------------------------------------------------------

resource "aws_route_table" "private" {
  vpc_id = module.api_setup.vpc_id

  # Traffic to Atlas VPC goes through the peering connection
  route {
    cidr_block                = var.ATLAS_VPC_CIDR
    vpc_peering_connection_id = mongodbatlas_network_peering.atlas_network_peering.connection_id
  }

  # All other outbound traffic exits through the NAT gateway
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = module.api_setup.nat_gateway_id
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-private-route-table"
  })
}

# ---------------------------------------------------------------------------
# 5. AWS — associate the route table with every private subnet
#    Without explicit associations, subnets fall back to the main route table
#    and Atlas traffic would not be routed correctly.
# ---------------------------------------------------------------------------

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = element(module.api_setup.private_subnets, count.index)
  route_table_id = aws_route_table.private.id
}
