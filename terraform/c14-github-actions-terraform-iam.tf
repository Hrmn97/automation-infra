# =============================================================================
# GitHub Actions — Terraform CI Role
#
# Purpose: Separate from the app-deploy role in c13.
#   - c13 role = used by service repos (sf-api, sf-admin, etc.) to push images
#     and update ECS services.  Least-privilege.
#   - THIS role = used by THIS repo (sf-terraform) to run terraform plan/apply.
#     Needs AdministratorAccess because Terraform manages every resource.
#
# The role is created only in the stage environment (count = 1 when env = stage)
# to avoid a duplicate-name conflict when both stage and prod apply runs target
# the same AWS account.
# =============================================================================

resource "aws_iam_role" "github_actions_terraform_role" {
  count = var.environment == "stage" ? 1 : 0

  name        = "github-actions-terraform"
  description = "Assumed by GitHub Actions (OIDC) in sf-terraform to run terraform plan/apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Any branch / event in sf-terraform can assume this role.
          # Narrowing to a specific branch would block plan runs on feature PRs.
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/sf-terraform:*"
        }
      }
    }]
  })

  tags = {
    Name      = "github-actions-terraform"
    ManagedBy = "terraform"
    Purpose   = "Terraform CI/CD via GitHub Actions"
  }
}

# AdministratorAccess is required: Terraform apply creates/modifies/deletes
# every resource in the stack (VPC, IAM, ECS, RDS, OpenSearch, etc.).
resource "aws_iam_role_policy_attachment" "github_actions_terraform_admin" {
  count = var.environment == "stage" ? 1 : 0

  role       = aws_iam_role.github_actions_terraform_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_actions_terraform_role_arn" {
  description = "ARN of the Terraform CI role — set this as STAGE_TF_ROLE_ARN in the GitHub stage environment secrets"
  value       = var.environment == "stage" ? aws_iam_role.github_actions_terraform_role[0].arn : "(created in stage environment only)"
}
