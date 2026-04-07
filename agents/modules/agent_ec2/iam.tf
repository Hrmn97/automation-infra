# IAM Role for agent instance
resource "aws_iam_role" "agent" {
  name_prefix = "${local.agent_full_name}-"
  description = "IAM role for OpenClaw agent: ${var.agent_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(
    var.tags,
    {
      Name  = "${local.agent_full_name}-role"
      Agent = var.agent_name
    }
  )
}

# Instance Profile
resource "aws_iam_instance_profile" "agent" {
  name_prefix = "${local.agent_full_name}-"
  role        = aws_iam_role.agent.name

  tags = merge(
    var.tags,
    {
      Name  = "${local.agent_full_name}-profile"
      Agent = var.agent_name
    }
  )
}

# Managed Policy - SSM Session Manager
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom Policy - CloudWatch Logs (scoped to agent's log group only)
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name_prefix = "cloudwatch-logs-"
  role        = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = [
        "${aws_cloudwatch_log_group.agent.arn}:*"
      ]
    }]
  })
}

# Custom Policy - Secrets Manager / Parameter Store (scoped to agent's namespace)
resource "aws_iam_role_policy" "secrets" {
  name_prefix = "secrets-"
  role        = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:/openclaw/agents/${var.agent_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/openclaw/agents/${var.agent_name}/*"
        ]
      },
      {
        # Allow listing to check if parameters exist
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Agent" = var.agent_name
          }
        }
      }
    ]
  })
}

# Custom Policy - Bedrock (scoped to specific model ARN and allowed regions)
resource "aws_iam_role_policy" "bedrock" {
  name_prefix = "bedrock-"
  role        = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = local.bedrock_model_arns
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.allowed_bedrock_regions
          }
        }
      },
      {
        # Required for OpenClaw's automatic Bedrock model discovery
        Effect   = "Allow"
        Action   = ["bedrock:ListFoundationModels"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.allowed_bedrock_regions
          }
        }
      }
    ]
  })
}

# Self-diagnostics: EC2, VPC, networking read-only
resource "aws_iam_role_policy" "self_ec2_read" {
  count       = var.enable_self_diagnostics ? 1 : 0
  name_prefix = "self-ec2-read-"
  role        = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DescribeInfra"
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeTags",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:DescribeNatGateways",
        "ec2:DescribeVpcEndpoints",
        "ec2:DescribeRouteTables",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeVolumes"
      ]
      Resource = "*"
    }]
  })
}

# Self-diagnostics: CloudWatch Logs read + Metrics
resource "aws_iam_role_policy" "self_cloudwatch_read" {
  count       = var.enable_self_diagnostics ? 1 : 0
  name_prefix = "self-cw-read-"
  role        = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOwnLogs"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:StopQuery"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.agent.arn}",
          "${aws_cloudwatch_log_group.agent.arn}:*"
        ]
      },
      {
        Sid    = "ListLogGroups"
        Effect = "Allow"
        Action = ["logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
      {
        Sid    = "ReadMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      }
    ]
  })
}

# Host metrics: CloudWatch agent writes metrics, agent can create dashboards/alarms
resource "aws_iam_role_policy" "host_metrics" {
  count       = var.enable_host_metrics ? 1 : 0
  name_prefix = "host-metrics-"
  role        = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CWAgentPutMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = var.host_metrics_namespace
          }
        }
      }
    ]
  })
}

# Self-diagnostics: IAM read on own role only
resource "aws_iam_role_policy" "self_iam_read" {
  count       = var.enable_self_diagnostics ? 1 : 0
  name_prefix = "self-iam-read-"
  role        = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "InspectOwnRole"
      Effect = "Allow"
      Action = [
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:GetInstanceProfile"
      ]
      Resource = [
        aws_iam_role.agent.arn,
        aws_iam_instance_profile.agent.arn
      ]
    }]
  })
}

# Additional IAM policies (passed as ARNs)
resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.additional_iam_policies)

  role       = aws_iam_role.agent.name
  policy_arn = each.value
}

# Example of how to add tool access later (S3 read-only)
# Uncomment and customize as needed
#
# variable "enable_s3_access" {
#   type        = bool
#   default     = false
#   description = "Enable S3 read-only access for agent"
# }
#
# variable "allowed_s3_buckets" {
#   type        = list(string)
#   default     = []
#   description = "List of S3 bucket ARNs agent can read from"
# }
#
# resource "aws_iam_role_policy" "s3_access" {
#   count = var.enable_s3_access ? 1 : 0
#   
#   name_prefix = "s3-access-"
#   role        = aws_iam_role.agent.id
#   
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "s3:GetObject",
#         "s3:ListBucket"
#       ]
#       Resource = concat(
#         var.allowed_s3_buckets,
#         [for b in var.allowed_s3_buckets : "${b}/*"]
#       )
#     }]
#   })
# }

# Example: DynamoDB read-only access
# resource "aws_iam_role_policy" "dynamodb_access" {
#   count = var.enable_dynamodb_access ? 1 : 0
#   
#   name_prefix = "dynamodb-access-"
#   role        = aws_iam_role.agent.id
#   
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "dynamodb:GetItem",
#         "dynamodb:Query",
#         "dynamodb:Scan",
#         "dynamodb:BatchGetItem"
#       ]
#       Resource = var.allowed_dynamodb_table_arns
#       Condition = {
#         StringEquals = {
#           "aws:RequestedRegion" = data.aws_region.current.name
#         }
#       }
#     }]
#   })
# }
