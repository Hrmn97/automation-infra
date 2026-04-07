# ─── Vision Training & Pipeline Infrastructure ─────────────────────────────
#
# S3 bucket for datasets + model artifacts, and scoped IAM policies for
# agent-one to launch/terminate GPU instances for YOLO training and
# full vision pipeline runs (YOLO → VLM → Cloud LLM → Report).
#
# All EC2 actions are restricted to:
#   - Allowed instance types only (default: g5.xlarge), tag-enforced
#   - Instances tagged Purpose=vision-training or Purpose=vision-pipeline
#   - eu-west-2 region only
#   - Specific subnets and security group only
#
# The agent CANNOT touch its own instance or any non-training resources.
#
# Spot instances use RunInstances with InstanceMarketOptions (not the legacy
# RequestSpotInstances API) to ensure instance type and tag restrictions apply.
# ────────────────────────────────────────────────────────────────────────────

# ─── Variables ──────────────────────────────────────────────────────────────

variable "enable_vision_training" {
  description = "Enable vision training infrastructure (S3 bucket + GPU launch permissions)"
  type        = bool
  default     = false
}

variable "vision_training_allowed_instance_types" {
  description = "EC2 instance types allowed for training (GPU)"
  type        = list(string)
  default     = ["g5.xlarge"]
}

# ─── S3 Bucket ──────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "vision_training" {
  count  = var.enable_vision_training ? 1 : 0
  bucket = "sf-vision-training"

  tags = merge(local.common_tags, {
    Name    = "sf-vision-training"
    Purpose = "vision-training"
  })
}

resource "aws_s3_bucket_versioning" "vision_training" {
  count  = var.enable_vision_training ? 1 : 0
  bucket = aws_s3_bucket.vision_training[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vision_training" {
  count  = var.enable_vision_training ? 1 : 0
  bucket = aws_s3_bucket.vision_training[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vision_training" {
  count  = var.enable_vision_training ? 1 : 0
  bucket = aws_s3_bucket.vision_training[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforce TLS-only access
resource "aws_s3_bucket_policy" "vision_training_tls_only" {
  count  = var.enable_vision_training ? 1 : 0
  bucket = aws_s3_bucket.vision_training[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.vision_training[0].arn,
        "${aws_s3_bucket.vision_training[0].arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "vision_training" {
  count  = var.enable_vision_training ? 1 : 0
  bucket = aws_s3_bucket.vision_training[0].id

  rule {
    id     = "expire-old-runs"
    status = "Enabled"

    filter {
      prefix = "runs/"
    }

    expiration {
      days = 90
    }
  }

  rule {
    id     = "ia-old-datasets"
    status = "Enabled"

    filter {
      prefix = "datasets/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# ─── Security Group for training instances ──────────────────────────────────

resource "aws_security_group" "vision_training" {
  count       = var.enable_vision_training ? 1 : 0
  name_prefix = "sf-vision-training-"
  description = "Security group for GPU training instances"
  vpc_id      = module.network.vpc_id

  # SSH from within VPC only (for EC2 Instance Connect)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "SSH from VPC (EC2 Instance Connect)"
  }

  # HTTPS egress only (for S3, SSM, package repos)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for S3, SSM, package repos"
  }

  # HTTP egress for package repos (pip, yum)
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for package repositories"
  }

  tags = merge(local.common_tags, {
    Name    = "sf-vision-training"
    Purpose = "vision-training"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ─── IAM Policy: S3 access to training bucket ──────────────────────────────

resource "aws_iam_role_policy" "vision_training_s3" {
  count       = var.enable_vision_training ? 1 : 0
  name_prefix = "vision-training-s3-"
  role        = module.agents["agent-one"].iam_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "VisionTrainingS3ReadWrite"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ]
      Resource = [
        aws_s3_bucket.vision_training[0].arn,
        "${aws_s3_bucket.vision_training[0].arn}/*"
      ]
    },
    {
      Sid    = "VisionTrainingS3VersionRecovery"
      Effect = "Allow"
      Action = [
        "s3:GetBucketVersioning",
        "s3:ListBucketVersions",
        "s3:GetObjectVersion"
      ]
      Resource = [
        aws_s3_bucket.vision_training[0].arn,
        "${aws_s3_bucket.vision_training[0].arn}/*"
      ]
    }]
  })
}

# ─── IAM Policy: Scoped EC2 for GPU training instances ─────────────────────

resource "aws_iam_role_policy" "vision_training_ec2" {
  count       = var.enable_vision_training ? 1 : 0
  name_prefix = "vision-training-ec2-"
  role        = module.agents["agent-one"].iam_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read-only describe actions (these don't support resource/tag scoping)
        Sid    = "DescribeForLaunch"
        Effect = "Allow"
        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "eu-west-2"
          }
        }
      },
      {
        # RunInstances on instance resource - restricted to allowed types + must tag Purpose
        Sid    = "RunTrainingInstances"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = [
          "arn:aws:ec2:eu-west-2:${local.account_id}:instance/*"
        ]
        Condition = {
          "ForAllValues:StringEquals" = {
            "ec2:InstanceType" = var.vision_training_allowed_instance_types
          }
          StringEquals = {
            "aws:RequestTag/Purpose" = ["vision-training", "vision-pipeline"]
          }
        }
      },
      {
        # RunInstances supporting resources - scoped to training SG + VPC subnets only
        Sid    = "RunTrainingInstanceResources"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = concat(
          [
            "arn:aws:ec2:eu-west-2::image/*",
            "arn:aws:ec2:eu-west-2:${local.account_id}:network-interface/*",
            "arn:aws:ec2:eu-west-2:${local.account_id}:volume/*",
          ],
          # Only the training security group
          [aws_security_group.vision_training[0].arn],
          # Only the VPC's private subnets
          [for sid in module.network.private_subnet_ids :
            "arn:aws:ec2:eu-west-2:${local.account_id}:subnet/${sid}"
          ],
        )
      },
      {
        # Tag on create - required for the Purpose tag enforcement above
        Sid    = "TagTrainingInstances"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = "arn:aws:ec2:eu-west-2:${local.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "RunInstances"
          }
        }
      },
      {
        # Terminate/stop/start - ONLY instances tagged Purpose=vision-training
        Sid    = "ManageTrainingInstances"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances"
        ]
        Resource = "arn:aws:ec2:eu-west-2:${local.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Purpose" = ["vision-training", "vision-pipeline"]
          }
        }
      },
      {
        # Pass role - only the vision training instance profile
        Sid    = "PassTrainingRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.vision_training_instance[0].arn
      }
    ]
  })
}

# ─── IAM Role for GPU training instances (so they can access S3) ───────────

resource "aws_iam_role" "vision_training_instance" {
  count       = var.enable_vision_training ? 1 : 0
  name        = "sf-vision-training-instance"
  description = "IAM role for GPU training instances - S3 access to training bucket"

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

  tags = merge(local.common_tags, {
    Purpose = "vision-training"
  })
}

resource "aws_iam_instance_profile" "vision_training" {
  count = var.enable_vision_training ? 1 : 0
  name  = "sf-vision-training-instance"
  role  = aws_iam_role.vision_training_instance[0].name

  tags = merge(local.common_tags, {
    Purpose = "vision-training"
  })
}

resource "aws_iam_role_policy" "vision_training_instance_s3" {
  count = var.enable_vision_training ? 1 : 0
  name  = "s3-training-bucket"
  role  = aws_iam_role.vision_training_instance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.vision_training[0].arn,
        "${aws_s3_bucket.vision_training[0].arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "vision_training_instance_bedrock" {
  count = var.enable_vision_training ? 1 : 0
  name  = "bedrock-invoke"
  role  = aws_iam_role.vision_training_instance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BedrockInvoke"
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = [
        "arn:aws:bedrock:*:*:inference-profile/eu.anthropic.*",
        "arn:aws:bedrock:*::foundation-model/anthropic.*",
        "arn:aws:bedrock:*:*:inference-profile/eu.amazon.*",
        "arn:aws:bedrock:*::foundation-model/amazon.*"
      ]
    }]
  })
}

# SSM for GPU instances too (so agent can manage via SSM)
resource "aws_iam_role_policy_attachment" "vision_training_ssm" {
  count      = var.enable_vision_training ? 1 : 0
  role       = aws_iam_role.vision_training_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ─── Explicit deny: protect agent's own instance ───────────────────────────

resource "aws_iam_role_policy" "vision_training_deny_self" {
  count       = var.enable_vision_training ? 1 : 0
  name_prefix = "vision-training-deny-self-"
  role        = module.agents["agent-one"].iam_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenySelfTerminate"
      Effect = "Deny"
      Action = [
        "ec2:TerminateInstances",
        "ec2:StopInstances"
      ]
      Resource = module.agents["agent-one"].instance_arn
    }]
  })
}

# ─── Explicit deny: block legacy spot API (forces RunInstances path) ───────

resource "aws_iam_role_policy" "vision_training_deny_legacy_spot" {
  count       = var.enable_vision_training ? 1 : 0
  name_prefix = "vision-training-deny-spot-"
  role        = module.agents["agent-one"].iam_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyLegacySpotAPI"
      Effect = "Deny"
      Action = [
        "ec2:RequestSpotInstances",
        "ec2:RequestSpotFleet"
      ]
      Resource = "*"
    }]
  })
}

# ─── SSM access for agent to manage vision instances ───────────────────────

resource "aws_iam_role_policy" "vision_ssm_access" {
  count = var.enable_vision_training ? 1 : 0
  name  = "ssm-vision-instances"
  role  = module.agents["agent-one"].iam_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Tag-conditioned: only allow SSM on vision-tagged EC2 instances
        Sid    = "SSMOnTaggedInstances"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:SendCommand"
        ]
        Resource = "arn:aws:ec2:eu-west-2:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Purpose" = ["vision-training", "vision-pipeline"]
          }
        }
      },
      {
        # SSM documents and sessions — no tag condition
        # (these resources don't support resource tags)
        Sid    = "SSMDocumentsAndSessions"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:SendCommand",
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = [
          "arn:aws:ssm:eu-west-2::document/AWS-RunShellScript",
          "arn:aws:ssm:eu-west-2::document/AWS-StartInteractiveCommand",
          "arn:aws:ssm:eu-west-2::document/SSM-SessionManagerRunShell",
          "arn:aws:ssm:eu-west-2:${data.aws_caller_identity.current.account_id}:session/*"
        ]
      },
      {
        # GetCommandInvocation/ListCommandInvocations need wildcard resource
        # (AWS doesn't support scoping these to specific instances)
        Sid    = "SSMCommandInvocations"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      },
      {
        # DescribeInstanceInformation doesn't support resource scoping
        Sid    = "SSMDescribe"
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstanceInformation"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─── EC2 Instance Connect: SSH without permanent keys ──────────────────────

resource "aws_iam_role_policy" "vision_ec2_instance_connect" {
  count = var.enable_vision_training ? 1 : 0
  name  = "ec2-instance-connect-vision"
  role  = module.agents["agent-one"].iam_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EC2InstanceConnectVision"
      Effect = "Allow"
      Action = "ec2-instance-connect:SendSSHPublicKey"
      Resource = "arn:aws:ec2:eu-west-2:${data.aws_caller_identity.current.account_id}:instance/*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/Purpose" = ["vision-training", "vision-pipeline"]
        }
      }
    }]
  })
}

# ─── Cost guardrail: CloudWatch alarm for training instances ───────────────

resource "aws_cloudwatch_metric_alarm" "vision_training_running" {
  count               = var.enable_vision_training ? 1 : 0
  alarm_name          = "sf-vision-training-instances-running"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningInstances"
  namespace           = "AWS/EC2"
  period              = 3600
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Alert if more than 1 training or pipeline instance is running (cost guardrail)"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Purpose = "vision-training"
  }

  tags = merge(local.common_tags, {
    Purpose = "vision-training"
  })
}
