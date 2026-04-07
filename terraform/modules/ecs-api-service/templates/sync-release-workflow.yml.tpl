name: Sync Release to Stage

on:
  push:
    tags:
      - "v*"

jobs:
  sync:
    uses: ${github_org}/github-workflows/.github/workflows/sync-release.yml@main
    # with:
    #   staging_branch: develop
    #   main_branch: master
