.PHONY: init plan apply show

init:
	terraform init

plan:
	terraform plan -var-file=prod.tfvars

apply:
	terraform apply -var-file=prod.tfvars

show:
	@echo "GCP Project: servefirst"
	@echo "Credentials: $$GOOGLE_APPLICATION_CREDENTIALS"
	@terraform output 2>/dev/null || echo "No outputs yet (run init first)"
