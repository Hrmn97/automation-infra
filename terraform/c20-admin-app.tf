# =============================================================================
# SF Admin App — S3 + CloudFront SPA deployment
#
# Internal admin dashboard for ServeFirst staff.
# See: https://servefirst.atlassian.net/wiki/spaces/Eng/pages/229408770
#
# What this file provisions:
#   Calls the s3-cloudfront-app module (terraform/modules/s3-cloudfront-app/),
#   which creates:
#     - Private S3 bucket (OAI-only access) + versioning + SSE + lifecycle
#     - CloudFront OAI + bucket policy
#     - ACM certificate (us-east-1) + Route53 DNS validation
#     - CloudFront distribution (HTTPS-only, SPA 403/404 → index.html,
#       security response headers)
#     - Route53 A alias record → CloudFront
#     - GitHub repository + branch protection + 10 workflow files (stage-only,
#       pushed to both main and stage branches)
#
# How the admin app fits in:
#   - Served from CloudFront, NOT behind the ALB — no listener rule needed.
#   - Authentication is handled by sf-auth-service (c19):
#       Browser → auth service (Google OIDC) → JWT → admin app API calls
#   - All API calls from the SPA go to the ALB via HTTPS (JWT required).
#   - ALLOWED_ORIGINS in c19-auth-service.tf is locked to this app's domain.
#
# Domain resolution (via module):
#   prod  → admin.servefirst.co.uk
#   stage → admin-stage.servefirst.co.uk
#   dev   → admin-dev.servefirst.co.uk
#
# Connections to the rest of the stack:
#   - c19-auth-service.tf — auth service's ALLOWED_ORIGINS must match the
#     domain resolved above.
#   - c13-github-actions-iam.tf — deploy role's S3 policy covers the
#     admin-stage/admin bucket via local.deploy_s3_buckets.
#   - c21-outputs.tf — re-exports admin_app_url and cloudfront_distribution_id
#     for CI cache-invalidation docs.
#
# Auth security note:
#   The SPA itself is public via CloudFront (no IP restriction).
#   Security is enforced at the API layer (JWT middleware) and auth service
#   (Google OIDC locked to @servefirst.co.uk accounts).
#   For stronger perimeter control, options include:
#     A) CloudFront Functions + Lambda@Edge for JWT validation
#     B) Cloudflare Access (zero-trust proxy in front of CloudFront)
#   Phase 1 uses auth service + JWT — revisit if compliance requires it.
# =============================================================================

module "admin_app" {
  source = "./modules/s3-cloudfront-app"

  providers = {
    aws           = aws
    aws.us-east-1 = aws.us-east-1
  }

  # Identity
  environment = var.environment
  app_name    = "admin"
  aws_region  = var.aws_region
  hosted_zone = var.hosted_zone_domain

  # GitHub repo (stage-only — both stage and prod deploy from the same repo)
  create_github_repo       = var.environment == "stage"
  github_org               = var.github_org
  app_display_name         = "SF Admin App"
  github_repo_visibility   = "private"
  github_repo_topics       = ["admin", "internal-tools", "refine-dev"]
  create_workflows         = true
  enable_branch_protection = true
  required_approvals       = 1
  node_version             = "22"

  common_tags = {
    Project     = "ServeFirst"
    Service     = "admin-app"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "admin_app_url" {
  value       = module.admin_app.app_url
  description = "HTTPS URL for the admin app (e.g. https://admin-stage.servefirst.co.uk)."
}

output "admin_app_cloudfront_domain" {
  value       = module.admin_app.cloudfront_domain_name
  description = "CloudFront *.cloudfront.net domain for the admin app."
}

output "admin_app_cloudfront_distribution_id" {
  value       = module.admin_app.cloudfront_distribution_id
  description = "CloudFront distribution ID — needed by CI for cache invalidation after deploy."
}

output "admin_app_s3_bucket" {
  value       = module.admin_app.s3_bucket_id
  description = "S3 bucket name — CI pushes built assets here."
}
