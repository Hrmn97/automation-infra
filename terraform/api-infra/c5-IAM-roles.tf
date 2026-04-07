# ============================================================
# c5-roles.tf
# IAM Roles and Policies:
#   - ECS Task Execution Role (pull images, read secrets)
#   - ECS Task Role (runtime permissions: S3, SQS, Bedrock, X-Ray)
#   - VPC Flow Logs Role
#   - EventBridge → ECS Role (for scheduled cron jobs)
# ============================================================

# ------------------------------------------------------------
# ECS Task Execution Role
# Used by the ECS agent to pull Docker images from ECR and
# fetch secrets/parameters from Secrets Manager / SSM.
# ------------------------------------------------------------

# Trust policy: only ECS tasks can assume this role
data "aws_iam_policy_document" "ecs_task_execution_role" {
  version = "2012-10-17"
  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.environment}-ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role.json
}

# Attach AWS-managed ECS execution policy (ECR pull, CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attach EC2 container service policy (needed for cluster registration)
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_att2" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Inline policy: allow SSM, Secrets Manager, and S3 access at task startup
# (broad for secrets bootstrap; consider scoping by path in future)
resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${var.environment}-task-execution-policy"
  role = aws_iam_role.ecs_task_execution_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:*", "secretsmanager:*", "s3:*"]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------
# ECS Task Role (Runtime)
# Used by container code at runtime — NOT the ECS agent.
# Grants access to CloudWatch, SQS, S3, X-Ray, and Bedrock.
# ------------------------------------------------------------

# Used to resolve account ID in ARN templates
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.environment}-ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })
}

# Container Insights, SQS messaging, and scoped S3 access
resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "${var.environment}-task-role-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudWatch metrics, log publishing, ECS introspection, SQS
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "ecs:ListClusters",
          "ecs:ListContainerInstances",
          "ecs:DescribeContainerInstances",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = "*"
      },
      {
        # S3 access for reports, images, and client uploads
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          "arn:aws:s3:::${var.environment == "prod" ? "app" : "stagev2"}.servefirst.co.uk.reports",
          "arn:aws:s3:::${var.environment == "prod" ? "app" : "stagev2"}.servefirst.co.uk.reports/*",
          "arn:aws:s3:::${var.environment == "prod" ? "app" : "stagev2"}.servefirst.co.uk.images",
          "arn:aws:s3:::${var.environment == "prod" ? "app" : "stagev2"}.servefirst.co.uk.images/*",
          var.client_uploads_bucket_arn,
          "${var.client_uploads_bucket_arn}/*",
        ]
      }
    ]
  })
}

# X-Ray tracing permissions for distributed request tracing
resource "aws_iam_role_policy" "ecs_task_xray" {
  name = "${var.environment}-ecs-task-xray"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries",
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Bedrock permissions for AI model invocation and Knowledge Base operations.
# Uses wildcard regions in ARNs to support cross-region inference profiles
# (e.g., eu.anthropic.claude-* routes to any EU region).
# Security is enforced via aws:RequestedRegion condition.
resource "aws_iam_role_policy" "ecs_task_bedrock" {
  name = "${var.environment}-ecs-task-bedrock"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Invoke foundation models from allowed regions only
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource  = ["arn:aws:bedrock:*::foundation-model/*"]
        Condition = { StringEquals = { "aws:RequestedRegion" = var.allowed_bedrock_regions } }
      },
      {
        # Invoke and describe cross-region inference profiles
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:GetInferenceProfile",
        ]
        Resource  = ["arn:aws:bedrock:*:*:inference-profile/*"]
        Condition = { StringEquals = { "aws:RequestedRegion" = var.allowed_bedrock_regions } }
      },
      {
        # List available models and inference profiles
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:ListInferenceProfiles",
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.allowed_bedrock_regions } }
      },
      {
        # Knowledge Base management (data sources, ingestion jobs, retrieval)
        Effect = "Allow"
        Action = [
          "bedrock:CreateDataSource",
          "bedrock:DeleteDataSource",
          "bedrock:GetDataSource",
          "bedrock:ListDataSources",
          "bedrock:UpdateDataSource",
          "bedrock:StartIngestionJob",
          "bedrock:StopIngestionJob",
          "bedrock:GetIngestionJob",
          "bedrock:ListIngestionJobs",
          "bedrock:IngestKnowledgeBaseDocuments",
          "bedrock:GetKnowledgeBase",
          "bedrock:ListKnowledgeBases",
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
          "bedrock:TagResource",
          "bedrock:UntagResource",
        ]
        Resource = "*"
      },
      {
        # S3 access for the raw Knowledge Base document bucket
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectAttributes",
          "s3:GetObjectTagging",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:PutObjectTagging",
        ]
        Resource = [
          var.kb_raw_bucket_arn,
          "${var.kb_raw_bucket_arn}/*",
        ]
      }
    ]
  })
}

# ------------------------------------------------------------
# VPC Flow Logs Role
# Allows the Flow Logs service to write captured traffic
# metadata to CloudWatch Logs.
# ------------------------------------------------------------

data "aws_iam_policy_document" "flowlogs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flowlogs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "flowlogs_role" {
  name               = "${var.environment}-flowlogs-role"
  assume_role_policy = data.aws_iam_policy_document.flowlogs_assume_role.json
}

resource "aws_iam_role_policy" "flowlogs_role_policy" {
  name   = "${var.environment}-flowlogs-policy"
  role   = aws_iam_role.flowlogs_role.id
  policy = data.aws_iam_policy_document.flowlogs_policy.json
}

# ------------------------------------------------------------
# EventBridge → ECS Role
# Allows EventBridge scheduled rules to trigger ECS tasks
# (used by all cron job event targets).
# ------------------------------------------------------------

resource "aws_iam_role" "eventbridge_ecs_role" {
  name = "${var.environment}-eventbridge_ecs_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "eventbridge_ecs_policy" {
  name        = "${var.environment}-eventbridge_ecs_policy"
  description = "Allows EventBridge to run ECS tasks for scheduled crons"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECS actions to start and inspect tasks/services
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:UpdateService",
        ]
        Resource = [
          aws_ecs_cluster.main.arn,
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/*",
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/*",
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/*",
        ]
      },
      {
        # Allow EventBridge to write to ECS-related log groups
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/cron-${var.environment}/*",
        ]
      },
      {
        # EventBridge must pass both ECS roles to RunTask
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = [aws_iam_role.ecs_task_execution_role.arn, aws_iam_role.ecs_task_role.arn]
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_ecs_policy_attachment" {
  role       = aws_iam_role.eventbridge_ecs_role.name
  policy_arn = aws_iam_policy.eventbridge_ecs_policy.arn
}
