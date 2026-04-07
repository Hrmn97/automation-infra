# sf-terraform

- 2 envs as prod or stage
- each contains a tfvars file which has the variable values
- use the following commands, backend is aws s3 and workspaces have been used to manage 2 envs
- used the following comands

```s
terraform workspace new prod
terraform workspace select prod
terraform plan/apply -var-file="prod.tfvars"

terraform workspace new stage
terraform workspace select stage
terraform plan/apply -var-file="stage.tfvars"
```

- ref https://dev.to/klenam_/working-with-workspaces-and-backends-in-terraform-2ja2

If destroying, need to first apply and add force destroy to buckets and may need to manually delete the acm certificate and/or the cloudfront distribution
