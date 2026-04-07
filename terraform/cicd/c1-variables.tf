# ============================================================
# c1-variables.tf
# All input variables for the CI/CD pipelines.
# ============================================================

# ------------------------------------------------------------
# General & System Settings
# ------------------------------------------------------------

variable "environment" {
  description = "The working environment for these resources (e.g., dev, stage, prod)."
  type        = string
}

variable "enable_github_actions" {
  description = "If true, disables CodePipeline triggers by changing the monitored branch to a dummy one, allowing GitHub Actions to orchestrate instead."
  type        = bool
  default     = false
}

# ------------------------------------------------------------
# Backend (API) Settings
# ------------------------------------------------------------

variable "api_full_repo_id" {
  description = "The exact GitHub repository string for the API."
  type        = string
}

variable "api_repo_branch" {
  description = "The git branch the API CodePipeline should monitor and build."
  type        = string
}

variable "api_domain_name" {
  description = "The final URL of the API. Used to inject a backend route pointer into the frontend React builds."
  type        = string
}

# ------------------------------------------------------------
# Primary Frontend Settings (sf-react-app)
# ------------------------------------------------------------

variable "fe_full_repo_id" {
  description = "The GitHub repository string for your primary React frontend codebase."
  type        = string
}

variable "fe_repo_branch" {
  description = "The git branch to monitor for the primary frontend and the ratings frontend."
  type        = string
}

variable "fe_domain_name" {
  description = "The target S3 Bucket acting as static website host for the primary frontend."
  type        = string
}

variable "cloudfront_distribution" {
  description = "The AWS CloudFront Distribution ID tied to the primary frontend, used for cache invalidation."
  type        = string
}

variable "s3_resource_buckets" {
  description = "Map of additional resource buckets that the frontend app might need programmatic references to."
  type        = map(string)
}

# ------------------------------------------------------------
# Secondary Frontend Settings (Front Ratings)
# ------------------------------------------------------------

variable "fe_repo_front" {
  description = "The GitHub repository string for the secondary React frontend app (e.g., front-ratings)."
  type        = string
}

variable "front_distribution" {
  description = "CloudFront Distribution ID specifically tied to the secondary frontend app for cache invalidation."
  type        = string
}

# ------------------------------------------------------------
# Third-Party Integrations & Secrets
# ------------------------------------------------------------

variable "heap_env_id" {
  description = "Environment ID for Heap Product Analytics."
  type        = string
}

variable "chargebee_key" {
  description = "Chargebee API public/publishable key."
  type        = string
}

variable "chargebee_site" {
  description = "Chargebee site name prefix."
  type        = string
}
