# ─── GCP OAuth Configuration ──────────────────────────────────────────────────
#
# Manages OAuth consent screen and client credentials for the SF Admin Dashboard.
# Uses Google OIDC for internal staff authentication (@servefirst.co.uk only).
#
# ─────────────────────────────────────────────────────────────────────────────

# Step 1: Configure the OAuth consent screen MANUALLY in GCP Console:
#   → APIs & Services → OAuth consent screen
#   → User type: Internal (restricts to @servefirst.co.uk)
#   → App name: "ServeFirst Admin"
#   → Scopes: email, profile, openid
#
# Terraform can't toggle Internal vs External after creation, so this is a
# one-time manual step.

# Step 2: Create the OAuth client via Terraform.
# Uncomment once the consent screen is configured.

# resource "google_project_service" "iap" {
#   project = var.gcp_project_id
#   service = "iap.googleapis.com"
#
#   disable_dependent_services = false
# }

# resource "google_iap_client" "sf_admin_dashboard" {
#   display_name = "SF Admin Dashboard"
#   brand        = "projects/${var.gcp_project_id}/brands/<BRAND_ID>"
# }

# ─── Outputs (uncomment when resources are active) ────────────────────────────

# output "oauth_client_id" {
#   description = "OAuth Client ID for SF Admin Dashboard"
#   value       = google_iap_client.sf_admin_dashboard.client_id
# }
#
# output "oauth_client_secret" {
#   description = "OAuth Client Secret (store in 1Password)"
#   value       = google_iap_client.sf_admin_dashboard.secret
#   sensitive   = true
# }
