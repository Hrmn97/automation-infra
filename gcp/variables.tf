# ─── GCP Variables ────────────────────────────────────────────────────────────

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = "servefirst"
}

variable "gcp_region" {
  description = "Default GCP region"
  type        = string
  default     = "europe-west2"
}

variable "environment" {
  description = "Deployment environment (prod, stage)"
  type        = string
  default     = "prod"
}
