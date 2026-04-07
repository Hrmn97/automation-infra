# =============================================================================
# sqs-worker-service module — GitHub repository management
#
# Only acts when create_github_repo = true AND environment = "stage".
# The repo is created once in stage; both stage and prod deployments run
# through the same repo via branch-based workflow triggers.
# =============================================================================

locals {
  repo_name            = "sf-${var.service_name}-service"
  full_repo_name       = "${var.github_org}/${local.repo_name}"
  service_display_name = var.service_display_name != "" ? var.service_display_name : title(replace(var.service_name, "-", " "))
}

resource "github_repository" "service_repo" {
  count = var.create_github_repo && var.environment == "stage" ? 1 : 0

  name        = local.repo_name
  description = "${local.service_display_name} — SQS Worker Service for ServeFirst"
  visibility  = var.github_repo_visibility

  auto_init              = true
  has_issues             = true
  has_projects           = false
  has_wiki               = false
  has_downloads          = false
  allow_merge_commit     = true
  allow_squash_merge     = true
  allow_rebase_merge     = true
  delete_branch_on_merge = true

  ignore_vulnerability_alerts_during_read = true

  topics = concat([
    "microservice",
    "sqs-worker",
    "aws",
    "ecs",
    "fargate",
    "terraform-managed",
  ], var.github_repo_topics)

  dynamic "template" {
    for_each = var.github_template_owner != "" && var.github_template_repo != "" ? [1] : []
    content {
      owner      = var.github_template_owner
      repository = var.github_template_repo
    }
  }
}

# GitHub initialises with 'main'; create stage branch then set it as default
resource "github_branch" "stage" {
  count      = var.create_github_repo && var.environment == "stage" ? 1 : 0
  repository = github_repository.service_repo[0].name
  branch     = "stage"
  depends_on = [github_repository.service_repo]
}

resource "github_branch_default" "stage" {
  count      = var.create_github_repo && var.environment == "stage" ? 1 : 0
  repository = github_repository.service_repo[0].name
  branch     = "stage"
  depends_on = [github_branch.stage]
}

resource "github_branch_protection" "main" {
  count         = var.create_github_repo && var.environment == "stage" && var.enable_branch_protection ? 1 : 0
  repository_id = github_repository.service_repo[0].node_id
  pattern       = "main"

  required_status_checks { strict = true }

  required_pull_request_reviews {
    required_approving_review_count = var.required_approvals
    dismiss_stale_reviews           = true
    require_code_owner_reviews      = var.require_code_owner_reviews
  }

  enforce_admins = var.enforce_admins_on_main

  depends_on = [
    github_repository_file.deploy_workflow,
    github_repository_file.hotfix_workflow,
    github_repository_file.release_workflow,
    github_repository_file.tag_release_workflow,
    github_repository_file.sync_release_workflow,
  ]
}

resource "github_branch_protection" "stage" {
  count         = var.create_github_repo && var.environment == "stage" && var.enable_branch_protection && var.protect_stage_branch ? 1 : 0
  repository_id = github_repository.service_repo[0].node_id
  pattern       = "stage"

  required_status_checks { strict = false }
  enforce_admins = false

  depends_on = [github_branch.stage]
}

# Workflow files — committed to the repo at creation time
resource "github_repository_file" "deploy_workflow" {
  count               = var.create_github_repo && var.environment == "stage" && var.create_workflows ? 1 : 0
  repository          = github_repository.service_repo[0].name
  branch              = "main"
  file                = ".github/workflows/deploy.yml"
  commit_message      = "chore: add deployment workflow"
  commit_author       = "Terraform"
  commit_email        = "terraform@servefirst.co.uk"
  overwrite_on_create = true

  content = templatefile("${path.module}/templates/deploy-workflow.yml.tpl", {
    service_name         = var.service_name
    service_display_name = local.service_display_name
    github_org           = var.github_org
    aws_region           = var.aws_region
  })
}

resource "github_repository_file" "hotfix_workflow" {
  count               = var.create_github_repo && var.environment == "stage" && var.create_workflows ? 1 : 0
  repository          = github_repository.service_repo[0].name
  branch              = "main"
  file                = ".github/workflows/hotfix.yml"
  commit_message      = "chore: add hotfix workflow"
  commit_author       = "Terraform"
  commit_email        = "terraform@servefirst.co.uk"
  overwrite_on_create = true

  content = templatefile("${path.module}/templates/hotfix-workflow.yml.tpl", {
    github_org = var.github_org
  })
}

resource "github_repository_file" "release_workflow" {
  count               = var.create_github_repo && var.environment == "stage" && var.create_workflows ? 1 : 0
  repository          = github_repository.service_repo[0].name
  branch              = "main"
  file                = ".github/workflows/release.yml"
  commit_message      = "chore: add release workflow"
  commit_author       = "Terraform"
  commit_email        = "terraform@servefirst.co.uk"
  overwrite_on_create = true

  content = templatefile("${path.module}/templates/release-workflow.yml.tpl", {
    github_org = var.github_org
  })
}

resource "github_repository_file" "tag_release_workflow" {
  count               = var.create_github_repo && var.environment == "stage" && var.create_workflows ? 1 : 0
  repository          = github_repository.service_repo[0].name
  branch              = "main"
  file                = ".github/workflows/tag-release.yml"
  commit_message      = "chore: add tag-release workflow"
  commit_author       = "Terraform"
  commit_email        = "terraform@servefirst.co.uk"
  overwrite_on_create = true

  content = templatefile("${path.module}/templates/tag-release-workflow.yml.tpl", {
    github_org = var.github_org
  })
}

resource "github_repository_file" "sync_release_workflow" {
  count               = var.create_github_repo && var.environment == "stage" && var.create_workflows ? 1 : 0
  repository          = github_repository.service_repo[0].name
  branch              = "main"
  file                = ".github/workflows/sync-release.yml"
  commit_message      = "chore: add sync-release workflow"
  commit_author       = "Terraform"
  commit_email        = "terraform@servefirst.co.uk"
  overwrite_on_create = true

  content = templatefile("${path.module}/templates/sync-release-workflow.yml.tpl", {
    github_org = var.github_org
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "github_repo_url" {
  value       = var.create_github_repo && var.environment == "stage" ? github_repository.service_repo[0].html_url : ""
  description = "GitHub repository URL (populated in stage only)."
}

output "github_repo_name" {
  value       = var.create_github_repo && var.environment == "stage" ? github_repository.service_repo[0].name : ""
  description = "GitHub repository name (populated in stage only)."
}

output "github_repo_full_name" {
  value       = var.create_github_repo && var.environment == "stage" ? local.full_repo_name : ""
  description = "GitHub repository full name org/repo (populated in stage only)."
}
