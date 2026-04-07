# ============================================================
# c4-frontend-pipelines.tf
# CI/CD Pipelines and CodeBuild configurations for the Frontends.
# Deployments target S3 source buckets.
# ============================================================

### cicd S3

## sf-react-app
resource "aws_codebuild_project" "fe_build_project" {
  name         = "${var.environment}-fe-codebuild-project"
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
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }
}

resource "aws_codepipeline" "frontend-pipeline" {
  name     = "${var.environment}-frontend-pipeline"
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
      output_artifacts = ["fe_source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.repo_connection.arn
        FullRepositoryId = var.fe_full_repo_id
        BranchName       = var.fe_repo_branch
      }
    }
  }

  stage {
    name = "BuildDeploy"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["fe_source_output"]
      output_artifacts = ["fe_build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.fe_build_project.id

        EnvironmentVariables = jsonencode(concat([
          {
            name  = "DeployBucket"
            value = var.fe_domain_name
            type  = "PLAINTEXT"
          },
          {
            name  = "FrontUrl"
            value = "https://${local.front_domain}"
            type  = "PLAINTEXT"
          },
          {
            name  = "Distribution"
            value = var.cloudfront_distribution
            type  = "PLAINTEXT"
          },
          {
            name  = "ApiUrl"
            value = var.api_domain_name
            type  = "PLAINTEXT"
          },
          {
            name  = "HeapEnvId"
            value = var.heap_env_id
            type  = "PLAINTEXT"
          },
          {
            name  = "ChargebeePublishableKey"
            value = var.chargebee_key
            type  = "PLAINTEXT"
          },
          {
            name  = "ChargebeeSite"
            value = var.chargebee_site
            type  = "PLAINTEXT"
          },
          ],
          [for k, v in var.s3_resource_buckets : {
            name  = upper("${k}_RESOURCE_URL")
            value = v
            type  = "PLAINTEXT"
          }]
        ))
      }
    }
  }
}


## front-ratings

locals {
  front_domain = var.environment == "prod" ? "front.servefirst.co.uk" : "front-${var.environment}.servefirst.co.uk"
}

resource "aws_codebuild_project" "fe_front_build_project" {
  name         = "${var.environment}-fr-front-codebuild-project"
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
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }
}

resource "aws_codepipeline" "frontend-front-pipeline" {
  name     = "${var.environment}-fe-front-pipeline"
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
      output_artifacts = ["fe_front_source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.repo_connection.arn
        FullRepositoryId = var.fe_repo_front
        BranchName       = var.fe_repo_branch
      }
    }
  }

  stage {
    name = "BuildDeploy"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["fe_front_source_output"]
      output_artifacts = ["fe_front_build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.fe_front_build_project.id

        EnvironmentVariables = jsonencode(concat([
          {
            name  = "DeployBucket"
            value = local.front_domain
            type  = "PLAINTEXT"
          },
          {
            name  = "Distribution"
            value = var.front_distribution
            type  = "PLAINTEXT"
          },
          {
            name  = "ApiUrl"
            value = var.api_domain_name
            type  = "PLAINTEXT"
          },
          {
            name  = "ReactAppUrl"
            value = var.fe_domain_name
            type  = "PLAINTEXT"
          },
          ]
        ))
      }
    }
  }
}
