# =============================================================================
# ecs-api-service module — IAM roles & policies
#
# Two roles, each only created when the caller doesn't supply a BYO ARN:
#   task_execution_role — ECS agent: pull ECR images, read Secrets Manager,
#                         fetch S3 env files, write CloudWatch logs.
#   task_role           — Container runtime: CW logs, ECS describe, X-Ray,
#                         plus any caller-supplied policy statements.
# =============================================================================

# -----------------------------------------------------------------------------
# Task Execution Role (ECS agent)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "task_execution_role" {
  count = var.task_execution_role_arn == "" ? 1 : 0

  name = "${var.environment}-${local.full_service_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, {
    Name      = "${var.environment}-${local.full_service_name}-execution-role"
    ManagedBy = "terraform"
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_role_policy" {
  count = var.task_execution_role_arn == "" ? 1 : 0

  role       = aws_iam_role.task_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Inline policy: CW logs + optional Secrets Manager + optional S3 env file
resource "aws_iam_role_policy" "task_execution_additional" {
  count = var.task_execution_role_arn == "" ? 1 : 0

  name = "${var.environment}-${local.full_service_name}-execution-additional"
  role = aws_iam_role.task_execution_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid    = "CWLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/ecs/${var.environment}-${local.full_service_name}",
          "arn:aws:logs:${var.aws_region}:*:log-group:/ecs/${var.environment}-${local.full_service_name}:*",
        ]
      }],
      length(var.secrets_arns) > 0 ? [{
        Sid      = "SecretsRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [for s in var.secrets_arns : s.valueFrom]
      }] : [],
      var.env_file_arn != "" ? [{
        Sid      = "S3EnvFile"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = [var.env_file_arn]
      }] : [],
    )
  })
}

# -----------------------------------------------------------------------------
# Task Role (container runtime)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "task_role" {
  count = var.task_role_arn == "" ? 1 : 0

  name = "${var.environment}-${local.full_service_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, {
    Name      = "${var.environment}-${local.full_service_name}-task-role"
    ManagedBy = "terraform"
  })
}

# Base permissions every HTTP service needs
resource "aws_iam_role_policy" "task_role_base" {
  count = var.task_role_arn == "" ? 1 : 0

  name = "${var.environment}-${local.full_service_name}-task-base"
  role = aws_iam_role.task_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CWLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSDescribe"
        Effect = "Allow"
        Action = ["ecs:DescribeTasks", "ecs:ListTasks"]
        Resource = "*"
      },
    ]
  })
}

# X-Ray tracing — always attached so services can opt-in without IAM changes
resource "aws_iam_role_policy" "task_role_xray" {
  count = var.task_role_arn == "" ? 1 : 0

  name = "${var.environment}-${local.full_service_name}-task-xray"
  role = aws_iam_role.task_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "XRay"
      Effect = "Allow"
      Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets",
        "xray:GetSamplingStatisticSummaries",
      ]
      Resource = "*"
    }]
  })
}

# Caller-supplied policy statements (e.g. Bedrock InvokeModel, S3, DynamoDB)
resource "aws_iam_role_policy" "task_role_custom" {
  count = var.task_role_arn == "" && length(var.task_role_policy_statements) > 0 ? 1 : 0

  name = "${var.environment}-${local.full_service_name}-task-custom"
  role = aws_iam_role.task_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for stmt in var.task_role_policy_statements : merge(
      {
        Effect   = stmt.effect
        Action   = stmt.actions
        Resource = stmt.resources
      },
      length(stmt.conditions) > 0 ? {
        Condition = {
          for cond in stmt.conditions : cond.test => { (cond.variable) = cond.values }
        }
      } : {}
    )]
  })
}

# -----------------------------------------------------------------------------
# Locals — resolve which role ARN to use in the task definition
# -----------------------------------------------------------------------------

locals {
  task_execution_role_arn = var.task_execution_role_arn != "" ? var.task_execution_role_arn : aws_iam_role.task_execution_role[0].arn
  task_role_arn           = var.task_role_arn != "" ? var.task_role_arn : aws_iam_role.task_role[0].arn
}
