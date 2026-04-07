bucket         = "tf-infra-automation-artifacts"
region         = "eu-west-2"
profile        = "sf-deploy"
dynamodb_table = "tf-state"
encrypt        = true
key            = "terraform/prod/terraform.tfstate"