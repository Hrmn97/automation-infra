name: Create Hotfix PR

on:
  workflow_dispatch:
    inputs:
      version_type:
        description: "Version type"
        required: true
        default: "patch"
        type: choice
        options:
          - major
          - minor
          - patch

jobs:
  create-hotfix:
    uses: ${github_org}/github-workflows/.github/workflows/hotfix.yml@main
    with:
      version_type: $${{ inputs.version_type }}
    # No secrets needed - workflow only uses GITHUB_TOKEN which is always available
