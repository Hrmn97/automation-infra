# Remote state for the stage stack. S3 key remains terraform/staging/... so it
# continues to match the object created by the legacy layout (do not rename
# without migrating state in S3).

bucket         = "stage-terraform-test-now"
region         = "eu-west-2"
profile        = "sf-deploy"
encrypt        = true
key            = "terraform/stage/terraform.tfstate"
use_lockfile   = true