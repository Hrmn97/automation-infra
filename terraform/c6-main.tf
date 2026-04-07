module "cloudfront_s3_website_with_domain" {
  source            = "./cloudfront-s3"
  environment       = var.environment
  hosted_zone       = var.hosted_zone_domain
  domain_name       = var.fe_domain_name
  front_domain_name = var.front_domain_name
  ### should have the acm cert created in us-east-1 from the mentioned domain
  upload_sample_file = false
}



module "api_setup" {

  source = "./api-infra"

  environment                 = var.environment
  project_id                  = var.project_id
  aws_region                  = var.aws_region
  az_count                    = var.az_count
  hosted_zone                 = var.hosted_zone_domain
  domain_name                 = var.api_domain_name
  app_port                    = var.api_service_port
  fargate_cpu                 = var.environment == "prod" ? 1024 : 512
  fargate_memory              = var.environment == "prod" ? 2048 : 1024
  JWT_secret_arn              = var.JWT_secret_arn
  vpc_cidr                    = var.vpc_cidr
  api_desired_instances_count = var.api_desired_instances_count
  sns_topic                   = aws_sns_topic.infrastructure_alerts.arn

  # Redis variables
  valkey_node_type = var.valkey_node_type

  # Service Discovery
  enable_service_discovery       = true
  service_discovery_namespace_id = aws_service_discovery_private_dns_namespace.internal.id

  # Shared Security Group - API now uses this too!
  use_shared_security_group    = true # Switch API to shared SG
  shared_security_group_id     = aws_security_group.ecs_shared_tasks.id
  enable_shared_security_group = false # No longer needed since API uses shared SG

  kb_raw_bucket_arn         = aws_s3_bucket.kb_raw.arn
  client_uploads_bucket_arn = aws_s3_bucket.client_uploads.arn

  # SendGrid configuration
  sendgrid_parse_subdomain = var.sendgrid_parse_subdomain
  # Bedrock cross-region inference profile support
  allowed_bedrock_regions = var.allowed_bedrock_regions
}

module "cicd" {

  source = "./cicd"

  environment             = var.environment
  api_domain_name         = var.api_domain_name
  api_full_repo_id        = var.api_repo
  api_repo_branch         = var.api_repo_branch
  fe_full_repo_id         = var.fe_repo
  fe_repo_front           = var.fe_repo_front
  fe_repo_branch          = var.fe_repo_branch
  fe_domain_name          = var.fe_domain_name
  cloudfront_distribution = module.cloudfront_s3_website_with_domain.cloudfront_dist_id
  front_distribution      = module.cloudfront_s3_website_with_domain.front_cloudfront_dist_id
  s3_resource_buckets     = module.cloudfront_s3_website_with_domain.s3_resource_buckets
  heap_env_id             = var.heap_env_id
  chargebee_key           = var.chargebee_key
  chargebee_site          = var.chargebee_site
  enable_github_actions   = var.enable_github_actions
}


