name: Create Release PR

on:
  workflow_dispatch:
    inputs:
      version_type:
        description: "Version type"
        required: true
        default: "minor"
        type: choice
        options:
          - major
          - minor
          - patch

jobs:
  release:
    uses: ${github_org}/github-workflows/.github/workflows/release.yml@main
    with:
      version_type: $${{ inputs.version_type }}
      # Optional: Override defaults
      # staging_branch: develop
      # main_branch: master
      # package_file: version.json
