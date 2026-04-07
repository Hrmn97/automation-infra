output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_ips" {
  description = "Elastic IPs of NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "vpc_endpoints" {
  description = "Map of VPC endpoint IDs"
  value = merge(
    { for k, v in aws_vpc_endpoint.interface : k => v.id },
    { "s3" = aws_vpc_endpoint.s3.id }
  )
}

output "kms_key_id" {
  description = "KMS key ARN for CloudWatch Logs encryption (CloudWatch requires ARN, not ID)"
  value       = var.enable_kms_encryption ? aws_kms_key.logs[0].arn : null
}

output "kms_key_arn" {
  description = "KMS key ARN for CloudWatch Logs encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.logs[0].arn : null
}
