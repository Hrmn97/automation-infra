name: Deploy ${service_display_name}

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
    uses: ${github_org}/github-workflows/.github/workflows/deploy-ecs.yml@main
    with:
      service_name: ${service_name}
      service_display_name: ${service_display_name}
      aws_region: ${aws_region}
      environment: $${{ inputs.environment }}
      branch: $${{ inputs.branch }}
    secrets: inherit
