# =============================================================================
# Outputs — root stack aggregation
#
# This file is the LAST to be applied (c21). It adds:
#   1. Grouped aggregation outputs that bundle related values for CI/CD scripts
#      and cross-stack consumers (not duplicates — individual outputs live in
#      each service's c* file and are listed in the index below).
#   2. Infrastructure-level outputs (MongoDB, Valkey) not covered elsewhere.
#   3. CloudFront/S3 outputs for the main React console and front site
#      (sourced from module.cloudfront_s3_website_with_domain in c6-main.tf).
#
# Output index — individual outputs already declared in c* files:
#   c8  : ecs_shared_tasks_security_group_id
#   c9  : service_discovery_namespace_id, service_discovery_namespace_name,
#          api_internal_endpoint, chat_internal_endpoint
#   c10 : client_uploads_bucket_name, client_uploads_bucket_arn,
#          transfer_server_id, transfer_server_endpoint
#   c11 : bedrock_logging (grouped)
#   c12 : kb_id, kb_arn, kb_raw_bucket_name, kb_collection_endpoint
#   c13 : github_actions_deploy_role_arn
#   c14 : pdf_service_queue_url, pdf_service_ecr_url
#   c15 : workflow_service_queue_url, workflow_service_ecr_url
#   c16 : syncreviews_service_queue_url, syncreviews_service_ecr_url
#   c17 : response_service_queue_url, response_service_ecr_url
#   c18 : chat_service_url, chat_ecr_repository_url,
#          chat_service_name, chat_log_group
#   c19 : auth_service_url, auth_ecr_repository_url,
#          auth_service_name, auth_log_group, auth_service_discovery_name
#   c20 : admin_app_url, admin_app_cloudfront_domain,
#          admin_app_cloudfront_distribution_id, admin_app_s3_bucket
# =============================================================================

# -----------------------------------------------------------------------------
# Infrastructure — MongoDB Atlas
# -----------------------------------------------------------------------------

output "mongo" {
  description = "MongoDB Atlas cluster connection strings (private VPC peering endpoints)."
  value = {
    connection_url_private     = try(mongodbatlas_cluster.cluster-vpc-peer.connection_strings[0].private, null)
    connection_url_private_srv = try(mongodbatlas_cluster.cluster-vpc-peer.connection_strings[0].private_srv, null)
  }
}

# -----------------------------------------------------------------------------
# Infrastructure — Valkey (Redis-compatible) cache
# -----------------------------------------------------------------------------

output "valkey" {
  description = "Valkey endpoint details — consumed by chat and auth service env vars."
  value = {
    endpoint          = module.api_setup.valkey_endpoint
    port              = module.api_setup.valkey_port
    connection_string = "redis://${module.api_setup.valkey_endpoint}:${module.api_setup.valkey_port}"
  }
}

# -----------------------------------------------------------------------------
# Main React console — CloudFront + S3
# (module.cloudfront_s3_website_with_domain declared in c6-main.tf)
# -----------------------------------------------------------------------------

output "cloudfront_domain_name" {
  description = "CloudFront domain name for the main React console."
  value       = module.cloudfront_s3_website_with_domain.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for the main React console — needed for CI cache invalidation."
  value       = module.cloudfront_s3_website_with_domain.cloudfront_dist_id
}

output "s3_bucket_name" {
  description = "S3 bucket name for the main React console deployment."
  value       = module.cloudfront_s3_website_with_domain.s3_bucket_name
}

output "s3_resource_buckets" {
  description = "All S3 resource buckets managed by the cloudfront-s3 stack."
  value       = module.cloudfront_s3_website_with_domain.s3_resource_buckets
}

output "front_cloudfront_distribution_id" {
  description = "CloudFront distribution ID for the customer-facing front site — needed for CI cache invalidation."
  value       = module.cloudfront_s3_website_with_domain.front_cloudfront_dist_id
}

output "iam_resource_user_key" {
  description = "IAM access key ID for the cloudfront-s3 deploy user."
  value       = module.cloudfront_s3_website_with_domain.iam_resource_user_key
}

output "iam_resource_user_secret" {
  description = "IAM secret access key for the cloudfront-s3 deploy user."
  value       = module.cloudfront_s3_website_with_domain.iam_resource_user_secret
  sensitive   = true
}

# -----------------------------------------------------------------------------
# SQS Worker Services — grouped aggregations for CI scripts
# (individual queue_url / ecr_url outputs live in each service's c* file)
# -----------------------------------------------------------------------------

output "pdf_service" {
  description = "PDF service — key endpoints and identifiers for CI/CD and ops runbooks."
  value = {
    queue_url          = module.pdf_service.queue_url
    dlq_url            = module.pdf_service.dlq_url
    queue_name         = module.pdf_service.queue_name
    ecr_repository_url = module.pdf_service.ecr_repository_url
    ecs_service_name   = module.pdf_service.ecs_service_name
    log_group          = module.pdf_service.log_group_name
  }
}

output "workflow_service" {
  description = "Workflow service — key endpoints and identifiers for CI/CD and ops runbooks."
  value = {
    queue_url          = module.workflow_service.queue_url
    dlq_url            = module.workflow_service.dlq_url
    queue_name         = module.workflow_service.queue_name
    ecr_repository_url = module.workflow_service.ecr_repository_url
    ecs_service_name   = module.workflow_service.ecs_service_name
    log_group          = module.workflow_service.log_group_name
  }
}

output "syncreviews_service" {
  description = "Sync-reviews service — key endpoints and identifiers for CI/CD and ops runbooks."
  value = {
    queue_url          = module.syncreviews_service.queue_url
    dlq_url            = module.syncreviews_service.dlq_url
    queue_name         = module.syncreviews_service.queue_name
    ecr_repository_url = module.syncreviews_service.ecr_repository_url
    ecs_service_name   = module.syncreviews_service.ecs_service_name
    log_group          = module.syncreviews_service.log_group_name
  }
}

output "response_service" {
  description = "Response service — key endpoints and identifiers for CI/CD and ops runbooks."
  value = {
    queue_url          = module.response_service.queue_url
    dlq_url            = module.response_service.dlq_url
    queue_name         = module.response_service.queue_name
    ecr_repository_url = module.response_service.ecr_repository_url
    ecs_service_name   = module.response_service.ecs_service_name
    log_group          = module.response_service.log_group_name
  }
}

# -----------------------------------------------------------------------------
# Client Uploads — grouped aggregation
# (individual outputs live in c10-client-uploads.tf)
# -----------------------------------------------------------------------------

output "client_uploads" {
  description = "Client uploads S3 bucket and Transfer Family SFTP server details."
  value = {
    bucket_name              = aws_s3_bucket.client_uploads.id
    bucket_arn               = aws_s3_bucket.client_uploads.arn
    transfer_server_id       = length(aws_transfer_server.client_uploads) > 0 ? aws_transfer_server.client_uploads[0].id : null
    transfer_server_endpoint = length(aws_transfer_server.client_uploads) > 0 ? aws_transfer_server.client_uploads[0].endpoint : null
  }
}

# -----------------------------------------------------------------------------
# Knowledge Base — grouped aggregation
# (individual kb_id / kb_arn outputs live in c12-kb.tf)
# -----------------------------------------------------------------------------

output "knowledge_base" {
  description = "Bedrock Knowledge Base — IDs and ARNs for API service env vars and IAM policies."
  value = {
    knowledge_base_id   = aws_bedrockagent_knowledge_base.kb.id
    knowledge_base_arn  = aws_bedrockagent_knowledge_base.kb.arn
    knowledge_base_name = aws_bedrockagent_knowledge_base.kb.name
    raw_bucket_name     = aws_s3_bucket.kb_raw.id
    raw_bucket_arn      = aws_s3_bucket.kb_raw.arn
  }
}
