# =============================================================================
# sqs-worker-service module — IAM roles & policies
#
# Two roles:
#   task_execution_role — used by the ECS AGENT to pull images, fetch env
#                         files from S3, read Secrets Manager, and write logs.
#   task_role           — used by the CONTAINER at runtime to consume SQS,
#                         write CloudWatch logs, and any caller-supplied extras.
# =============================================================================

# -----------------------------------------------------------------------------
# Task Execution Role (ECS agent)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "task_execution_role" {
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
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow ECS agent to fetch the .env file from S3 (when env_file_arn is set)
resource "aws_iam_role_policy" "task_execution_s3_env" {
  count = var.env_file_arn != "" ? 1 : 0
  name  = "${var.environment}-${local.full_service_name}-s3-env-access"
  role  = aws_iam_role.task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:GetBucketLocation"]
      Resource = [
        var.env_file_arn,
        # Grant access to all objects in the same bucket as the env file
        "${replace(var.env_file_arn, "/\\/.*$/", "")}/*",
      ]
    }]
  })
}

# Allow ECS agent to fetch Secrets Manager secrets (when secrets_arns is set)
resource "aws_iam_role_policy" "execution_secrets_access" {
  count = length(var.secrets_arns) > 0 ? 1 : 0
  name  = "${var.environment}-${local.full_service_name}-execution-secrets"
  role  = aws_iam_role.task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.secrets_arns
    }]
  })
}

# Caller-supplied execution role policies (e.g. KMS decrypt for encrypted images)
resource "aws_iam_role_policy_attachment" "additional_execution_policies" {
  count      = length(var.additional_execution_role_policies)
  role       = aws_iam_role.task_execution_role.name
  policy_arn = var.additional_execution_role_policies[count.index]
}

# -----------------------------------------------------------------------------
# Task Role (container runtime)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "task_role" {
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

# SQS consumer — receive, delete, inspect, extend visibility
resource "aws_iam_role_policy" "sqs_consumer_policy" {
  name = "${var.environment}-${local.full_service_name}-sqs-consumer"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ChangeMessageVisibility",
      ]
      Resource = [
        aws_sqs_queue.service_queue.arn,
        aws_sqs_queue.service_dlq.arn,
      ]
    }]
  })
}

# CloudWatch Logs — container writes its own log stream
resource "aws_iam_role_policy" "cloudwatch_logs_policy" {
  name = "${var.environment}-${local.full_service_name}-cloudwatch-logs"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/ecs/${var.environment}-${local.full_service_name}:*"
    }]
  })
}

# Caller-supplied task role policies (e.g. S3 access, Bedrock, DynamoDB)
resource "aws_iam_role_policy_attachment" "additional_task_policies" {
  count      = length(var.additional_task_role_policies)
  role       = aws_iam_role.task_role.name
  policy_arn = var.additional_task_role_policies[count.index]
}
