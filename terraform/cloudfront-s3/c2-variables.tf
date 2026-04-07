# ---------------------------------------------------------------------------
# Input variables for the cloudfront-s3 module
# ---------------------------------------------------------------------------

variable "domain_name" {
  description = "Primary domain name — also used as the main S3 bucket name (e.g. app.servefirst.co.uk)"
  type        = string
}

variable "front_domain_name" {
  description = "Domain name of the consumer-facing front site passed in by the caller"
  type        = string
}

variable "environment" {
  description = "Deployment environment — controls domain names, CORS origins, and API origin"
  type        = string
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "hosted_zone" {
  description = "Route53 hosted zone name (e.g. servefirst.co.uk) — required when use_default_domain = false"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all taggable resources in this module"
  type        = map(string)
  default     = {}
}

variable "price_class" {
  description = "CloudFront price class — controls which edge locations serve content. PriceClass_100 = US/Canada/Europe only (lowest cost)"
  type        = string
  default     = "PriceClass_100"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "use_default_domain" {
  description = "If true, skip Route53/ACM and serve via the default CloudFront domain (*.cloudfront.net). Intended for quick testing only."
  type        = bool
  default     = false
}

variable "upload_sample_file" {
  description = "Upload a sample HTML file to the main S3 bucket on apply — useful for smoke-testing a fresh deployment"
  type        = bool
  default     = false
}

variable "buckets" {
  description = "Suffixes for additional resource S3 buckets. Each bucket is named {domain_name}.{suffix} (e.g. app.servefirst.co.uk.images)"
  type        = list(string)
  default     = ["images", "reports"]
}
