name: Deploy ${app_display_name}

on:
  # Automatic deployment on branch push
  push:
    branches: [main, stage]

  # Manual deployment of any branch
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment to deploy to"
        required: true
        type: choice
        options:
          - staging
          - production
      branch:
        description: "Branch to deploy (optional, defaults to the branch selected in 'Use workflow from')"
        required: false
        type: string

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    uses: ${github_org}/github-workflows/.github/workflows/deploy-s3-cloudfront.yml@main
    with:
      app_name: ${app_name}
      app_display_name: ${app_display_name}
      aws_region: ${aws_region}
      node_version: "${node_version}"
      environment: $${{ inputs.environment }}
      branch: $${{ inputs.branch }}
    secrets: inherit
