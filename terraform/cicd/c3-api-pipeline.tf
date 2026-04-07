# ============================================================
# c3-api-pipeline.tf
# CI/CD Pipeline and CodeBuild configurations for the API.
# Deployments target ECS Fargate.
# Also provisions the shared S3 bucket for codepipeline artifacts.
# ============================================================

#build the bucket for our codepipeline artifacts
resource "aws_s3_bucket" "codepipeline-artifacts" {
  bucket = "${var.environment}-codepipeline-artifacts-common"
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "codepipeline-artifacts" {
  bucket = aws_s3_bucket.codepipeline-artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block Public Access
resource "aws_s3_bucket_public_access_block" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline-artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline-artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

### cicd api

## codebuild project 


resource "aws_codebuild_project" "api_build_project" {
  name         = "${var.environment}-api-codebuild-project"
  service_role = aws_iam_role.codebuild-role.arn

  artifacts {
    type = "CODEPIPELINE"
  }


  source {
    type            = "CODEPIPELINE"
    location        = aws_s3_bucket.codepipeline-artifacts.bucket
    git_clone_depth = "0"
    buildspec       = "buildspec.yml"
  }


  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }
}

resource "aws_codestarconnections_connection" "repo_connection" {
  name          = "${var.environment}-git-repo-connection"
  provider_type = "GitHub"
}


### api pipeline
resource "aws_codepipeline" "api_pipeline" {
  name     = "${var.environment}-api-pipeline"
  role_arn = aws_iam_role.AWSCodePipelineServiceRole.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline-artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["api_source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.repo_connection.arn
        FullRepositoryId = var.api_full_repo_id
        BranchName       = var.enable_github_actions ? "disabled-for-github-actions" : var.api_repo_branch
      }
    }
  }
  ### BUILD
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["api_source_output"]
      output_artifacts = ["api_build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.api_build_project.id
        EnvironmentVariables = jsonencode([
          {
            name  = "ENVIRONMENT"
            value = var.environment
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  ### DEPLOY
  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["api_build_output"]

      configuration = {
        ClusterName = "${var.environment}-fargate-cluster"
        ServiceName = "${var.environment}-api-service"
        FileName    = "imagedefinitions.json"
      }
    }
    # Deploy the cron service
    dynamic "action" {
      for_each = var.environment == "prod" ? [1] : []
      content {
        name            = "Deploy_Cron_Service"
        category        = "Deploy"
        owner           = "AWS"
        provider        = "ECS"
        version         = "1"
        input_artifacts = ["api_build_output"]

        configuration = {
          ClusterName = "${var.environment}-fargate-cluster"
          ServiceName = "${var.environment}-cron-service"
          FileName    = "imagedefinitions-cron.json"
        }
      }
    }
  }
}
