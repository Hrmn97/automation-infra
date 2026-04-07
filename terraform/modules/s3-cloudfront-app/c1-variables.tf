# =============================================================================
# s3-cloudfront-app module — input variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (dev, stage, prod)."
  type        = string
}

variable "app_name" {
  description = "Short app name used in resource naming, e.g. 'admin'. Module derives the domain from this."
  type        = string
}

variable "aws_region" {
  description = "AWS region for S3 and other non-CloudFront resources."
  type        = string
  default     = "eu-west-2"
}

variable "hosted_zone" {
  description = "Route53 hosted zone name, e.g. 'servefirst.co.uk'."
  type        = string
  default     = "servefirst.co.uk"
}

# -----------------------------------------------------------------------------
# Domain
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Override the computed domain name. When empty: prod → <app>.servefirst.co.uk, others → <app>-<env>.servefirst.co.uk."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudFront
# -----------------------------------------------------------------------------

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 = US/EU/Canada only (cheapest)."
  type        = string
  default     = "PriceClass_100"
}

variable "default_root_object" {
  description = "Object CloudFront serves when the root URL is requested."
  type        = string
  default     = "index.html"
}

variable "spa_error_page" {
  description = "Page served for 403/404 responses — enables client-side SPA routing."
  type        = string
  default     = "/index.html"
}

variable "default_ttl" {
  description = "Default CloudFront cache TTL in seconds."
  type        = number
  default     = 86400 # 1 day
}

variable "max_ttl" {
  description = "Maximum CloudFront cache TTL in seconds."
  type        = number
  default     = 31536000 # 1 year
}

variable "min_ttl" {
  description = "Minimum CloudFront cache TTL in seconds."
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# Security headers
# -----------------------------------------------------------------------------

variable "enable_security_headers" {
  description = "Attach a CloudFront response headers policy with HSTS, X-Frame-Options, X-Content-Type-Options, and optional CSP."
  type        = bool
  default     = true
}

variable "custom_csp" {
  description = "Content-Security-Policy header value. Each SPA has different requirements — leave empty to skip CSP."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# S3 lifecycle
# -----------------------------------------------------------------------------

variable "noncurrent_version_expiration_days" {
  description = "Days before noncurrent S3 object versions are deleted."
  type        = number
  default     = 90
}

variable "abort_multipart_upload_days" {
  description = "Days before incomplete multipart uploads are aborted."
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Tagging
# -----------------------------------------------------------------------------

variable "common_tags" {
  description = "Tags merged onto every resource created by this module."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# GitHub repo management (optional, stage-only)
# -----------------------------------------------------------------------------

variable "create_github_repo" {
  description = "Create a GitHub repository for this app. Only acts in stage."
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub organisation."
  type        = string
  default     = "servefirstcx"
}

variable "app_display_name" {
  description = "Human-readable app name used in repo descriptions and workflow files."
  type        = string
  default     = ""
}

variable "github_repo_visibility" {
  description = "GitHub repository visibility."
  type        = string
  default     = "private"
  validation {
    condition     = contains(["private", "public", "internal"], var.github_repo_visibility)
    error_message = "github_repo_visibility must be private, public, or internal."
  }
}

variable "github_repo_topics" {
  description = "Extra GitHub topics appended to the default set."
  type        = list(string)
  default     = []
}

variable "github_template_owner" {
  description = "Owner of a GitHub template repo to initialise from."
  type        = string
  default     = ""
}

variable "github_template_repo" {
  description = "Name of a GitHub template repo to initialise from."
  type        = string
  default     = ""
}

variable "create_workflows" {
  description = "Commit GitHub Actions workflow files into the new repo."
  type        = bool
  default     = true
}

variable "enable_branch_protection" {
  description = "Enable branch protection on main and stage branches."
  type        = bool
  default     = true
}

variable "required_approvals" {
  description = "PR approvals required to merge to main."
  type        = number
  default     = 1
}

variable "require_code_owner_reviews" {
  description = "Require code-owner review on PRs to main."
  type        = bool
  default     = true
}

variable "enforce_admins_on_main" {
  description = "Apply branch-protection rules to admins on main."
  type        = bool
  default     = false
}

variable "protect_stage_branch" {
  description = "Apply lighter branch-protection rules to the stage branch."
  type        = bool
  default     = true
}

variable "node_version" {
  description = "Node.js version used in CI/CD workflow templates."
  type        = string
  default     = "22"
}
