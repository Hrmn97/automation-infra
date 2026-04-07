# EBS Snapshot Lifecycle Policy (AWS DLM)
# Creates automated hourly and daily snapshots of the agent's root EBS volume.

# IAM role for DLM service
resource "aws_iam_role" "dlm" {
  count       = var.enable_ebs_snapshots ? 1 : 0
  name_prefix = "${local.agent_full_name}-dlm-"
  description = "DLM lifecycle role for ${var.agent_name} EBS snapshots"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "dlm.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name  = "${local.agent_full_name}-dlm-role"
    Agent = var.agent_name
  })
}

resource "aws_iam_role_policy" "dlm" {
  count       = var.enable_ebs_snapshots ? 1 : 0
  name_prefix = "dlm-snapshots-"
  role        = aws_iam_role.dlm[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*::snapshot/*"
      },
      {
        # KMS permissions required for snapshots of encrypted EBS volumes
        Sid    = "KMSForEncryptedSnapshots"
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })
}

# DLM Lifecycle Policy — targets the agent's EBS volume via instance tag
resource "aws_dlm_lifecycle_policy" "agent_snapshots" {
  count              = var.enable_ebs_snapshots ? 1 : 0
  description        = "EBS snapshot policy for ${var.agent_name}"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    # Target volumes attached to this specific agent instance
    target_tags = {
      Name  = "${local.agent_full_name}-root"
      Agent = var.agent_name
    }

    # Schedule 1: Hourly snapshots, retain 72 (3 days)
    schedule {
      name = "${var.agent_name}-hourly"

      create_rule {
        interval      = 1
        interval_unit = "HOURS"
        times         = ["00:00"]
      }

      retain_rule {
        count = var.snapshot_hourly_retain
      }

      tags_to_add = {
        SnapshotType = "hourly"
        Agent        = var.agent_name
        ManagedBy    = "DLM"
      }

      copy_tags = true
    }

    # Schedule 2: Daily snapshots, retain 30 (1 month)
    schedule {
      name = "${var.agent_name}-daily"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"] # 3 AM UTC — low activity window
      }

      retain_rule {
        count = var.snapshot_daily_retain
      }

      tags_to_add = {
        SnapshotType = "daily"
        Agent        = var.agent_name
        ManagedBy    = "DLM"
      }

      copy_tags = true
    }
  }

  tags = merge(var.tags, {
    Name  = "${local.agent_full_name}-snapshot-policy"
    Agent = var.agent_name
  })
}
