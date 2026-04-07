name: Tag Release

on:
  pull_request:
    types: [closed]
    branches: [main]

jobs:
  tag:
    uses: ${github_org}/github-workflows/.github/workflows/tag-release.yml@main
    secrets: inherit
    # with:
    #   main_branch: master
    #   release_label: release
    #   tag_prefix: v
