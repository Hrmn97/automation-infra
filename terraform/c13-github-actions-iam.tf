# =============================================================================
# GitHub Actions — OIDC Provider + Deployment IAM Role & Policy
#
# How OIDC works here:
#   GitHub Actions mints a short-lived JWT for every workflow run.
#   AWS trusts that JWT because we register GitHub's OIDC issuer as an
#   Identity Provider in IAM.  The runner exchanges the JWT for temporary
#   STS credentials via sts:AssumeRoleWithWebIdentity — no long-lived
#   access keys ever exist in GitHub Secrets.
#
# What this file provisions:
#   1. aws_iam_openid_connect_provider — account-level singleton (no count).
#      Both stage and prod share this provider; only the roles are per-env.
#   2. aws_iam_role (github_actions_deploy_role) — the role a workflow assumes.
#      Trust policy is locked to:
#        a. audience  = "sts.amazonaws.com"          (prevents token reuse)
#        b. sub claim = "repo:<org>/<repo>:ref:refs/heads/<branch>"
#           → only the exact repo + branch combination can assume the role,
#             NOT any repo in the org (source was too broad).
#   3. aws_iam_policy (github_actions_deploy_policy) — least-privilege policy
#      scoped to environment-prefixed resources wherever possible.
#   4. aws_iam_role_policy_attachment — attaches policy to role.
# =============================================================================

locals {
  deploy_s3_buckets = {
    stage = [
      "stagev2.servefirst.co.uk",
      "front-stage.servefirst.co.uk",
      "admin-stage.servefirst.co.uk",
    ]
    prod = [
      "app.servefirst.co.uk",
      "front.servefirst.co.uk",
      "admin.servefirst.co.uk",
    ]
  }

  # Flatten bucket names into ARN pairs (bucket-level + object-level)
  deploy_s3_bucket_arns = flatten([
    for bucket in lookup(local.deploy_s3_buckets, var.environment, []) : [
      "arn:aws:s3:::${bucket}",
      "arn:aws:s3:::${bucket}/*",
    ]
  ])

  # OIDC sub-claim for the deploy role.
  # Locked to a specific repo + branch to prevent any other repo in the org
  # from assuming this role (the source used a wildcard "<org>/*:*").
  # Format: repo:<org>/<repo>:ref:refs/heads/<branch>
  gh_oidc_sub = "repo:${var.github_org}/${var.github_deploy_repo}:ref:refs/heads/${var.github_deploy_branch}"
}

# -----------------------------------------------------------------------------
# OIDC Identity Provider (account-level singleton — no count)
#
# Thumbprints: GitHub rotates these occasionally.
# Current valid set as of 2024: 6938fd4d... and 1c58a3a8...
# Check https://github.blog/changelog/ for rotation notices.
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Name      = "github-actions-oidc"
    ManagedBy = "terraform"
  }

  lifecycle {
    # Deleting this breaks ALL environments — require explicit targeting
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Deployment Role (per-environment, gated by enable_github_actions)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "github_actions_deploy_role" {
  count = var.enable_github_actions ? 1 : 0

  name = "${var.environment}-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # Both conditions must be under ONE StringEquals key — HCL jsonencode
        # silently drops duplicate keys, so two separate StringEquals blocks
        # would cause the first (aud check) to be overwritten and lost.
        StringEquals = {
          # Prevents a token issued for another AWS service being replayed here
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Locked to one repo + branch — only that exact combo can assume this role
          "token.actions.githubusercontent.com:sub" = local.gh_oidc_sub
        }
      }
    }]
  })

  tags = {
    Name        = "${var.environment}-github-actions-deploy"
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "OIDC-based deployment role for CI/CD"
  }
}

# -----------------------------------------------------------------------------
# Deployment Policy — least-privilege, scoped to environment where possible
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "github_actions_deploy_policy" {
  count = var.enable_github_actions ? 1 : 0

  name        = "${var.environment}-github-actions-deploy-policy"
  description = "Least-privilege policy for GitHub Actions OIDC deployments (${var.environment})"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # ------------------------------------------------------------------
      # ECR — GetAuthorizationToken must be on * (AWS requirement)
      # ------------------------------------------------------------------
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },

      # ------------------------------------------------------------------
      # ECR — push to env-prefixed repos only
      # ------------------------------------------------------------------
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${var.project_id}:repository/${var.environment}-*",
        ]
      },

      # ------------------------------------------------------------------
      # ECR — pull from env repos + shared "node" base image repo
      # ------------------------------------------------------------------
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${var.project_id}:repository/${var.environment}-*",
          "arn:aws:ecr:${var.aws_region}:${var.project_id}:repository/node",
        ]
      },

      # ------------------------------------------------------------------
      # ECS — update services in the environment cluster only
      # ------------------------------------------------------------------
      {
        Sid    = "ECSServiceUpdate"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
        ]
        Resource = [
          "arn:aws:ecs:${var.aws_region}:${var.project_id}:service/${var.environment}-*/*",
        ]
      },

      # ------------------------------------------------------------------
      # ECS — task definitions (RegisterTaskDefinition requires *)
      # ------------------------------------------------------------------
      {
        Sid    = "ECSTaskDef"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
        ]
        Resource = ["*"]
      },

      # ------------------------------------------------------------------
      # ECS — list/describe tasks scoped to env cluster via condition
      # ------------------------------------------------------------------
      {
        Sid    = "ECSTasksRead"
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:DescribeTasks",
        ]
        Resource = ["*"]
        Condition = {
          ArnLike = {
            "ecs:cluster" = "arn:aws:ecs:${var.aws_region}:${var.project_id}:cluster/${var.environment}-*"
          }
        }
      },

      # ------------------------------------------------------------------
      # IAM — PassRole scoped to env-prefixed roles + ECS tasks only
      # ------------------------------------------------------------------
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          "arn:aws:iam::${var.project_id}:role/${var.environment}-*",
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["ecs-tasks.amazonaws.com"]
          }
        }
      },

      # ------------------------------------------------------------------
      # CloudWatch Logs — scoped to /ecs/<env>-* log groups
      # ------------------------------------------------------------------
      {
        Sid    = "CWLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${var.project_id}:log-group:/ecs/${var.environment}-*",
          "arn:aws:logs:${var.aws_region}:${var.project_id}:log-group:/ecs/${var.environment}-*:*",
        ]
      },

      # ------------------------------------------------------------------
      # Secrets Manager — env-prefixed secrets only
      # ------------------------------------------------------------------
      {
        Sid    = "SecretsRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.project_id}:secret:${var.environment}-*",
          # MongoDB Atlas private key — shared across environments, read by the Atlas provider
          "arn:aws:secretsmanager:${var.aws_region}:${var.project_id}:secret:MONGO_ATLAS_ORG_PRIVATE_KEY*",
        ]
      },

      # ------------------------------------------------------------------
      # S3 — CI artifact bucket (env-prefixed keys) + frontend deploy buckets
      # ListBucket must be on the bucket ARN (no key suffix); object actions
      # use key-prefix ARNs.
      # ------------------------------------------------------------------
      {
        Sid    = "S3DeployList"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          # Bucket-level ARN required for ListBucket
          "arn:aws:s3:::tf-infra-automation-artifacts",
          "arn:aws:s3:::${var.environment}-*",
        ]
      },
      {
        Sid    = "S3DeployObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = concat(
          [
            # CodePipeline artifact bucket — env-scoped key prefix
            "arn:aws:s3:::tf-infra-automation-artifacts/${var.environment}*",
            "arn:aws:s3:::tf-infra-automation-artifacts/${var.environment}*/*",
            # Terraform remote state — key is terraform/<environment>/terraform.tfstate
            "arn:aws:s3:::tf-infra-automation-artifacts/terraform/${var.environment}/*",
            # Any env-prefixed S3 bucket (e.g. stage-servefirst-client-uploads)
            "arn:aws:s3:::${var.environment}-*",
            "arn:aws:s3:::${var.environment}-*/*",
          ],
          # Hardcoded frontend buckets per env (see locals.deploy_s3_buckets)
          local.deploy_s3_bucket_arns,
        )
      },

      # ------------------------------------------------------------------
      # DynamoDB — Terraform state locking (table shared across environments)
      # ------------------------------------------------------------------
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = ["arn:aws:dynamodb:${var.aws_region}:${var.project_id}:table/tf-state"]
      },

      # ------------------------------------------------------------------
      # CloudFront — cache invalidation after frontend deploys
      # CloudFront distribution IDs are not known at policy-write time;
      # * is the only practical scope here.
      # ------------------------------------------------------------------
      {
        Sid    = "CloudFrontInvalidate"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:ListInvalidations",
        ]
        Resource = ["*"]
      },
    ]
  })

  tags = {
    Name        = "${var.environment}-github-actions-deploy-policy"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Attach policy to role
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "github_actions_deploy" {
  count = var.enable_github_actions ? 1 : 0

  role       = aws_iam_role.github_actions_deploy_role[0].name
  policy_arn = aws_iam_policy.github_actions_deploy_policy[0].arn
}

# ReadOnlyAccess allows terraform plan to describe/list all AWS resources
# without granting any write permissions beyond the custom deploy policy above.
resource "aws_iam_role_policy_attachment" "github_actions_read_only" {
  count = var.enable_github_actions ? 1 : 0

  role       = aws_iam_role.github_actions_deploy_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

output "github_actions_deploy_role_arn" {
  value       = var.enable_github_actions ? aws_iam_role.github_actions_deploy_role[0].arn : ""
  description = "ARN of the OIDC-based GitHub Actions deploy role. Set as AWS_ROLE_ARN in each repo's workflow."
}
