# Casino Property Cell Terraform (GCP)

Terraform for isolated casino property cells.

## Plan-only flow
```bash
terraform init
terraform validate
terraform plan
```

## GCP provider
```hcl
provider "google" {
  project = "casino-ai-platform"
  region  = "us-central1"
}
```

## Add a new property
Add one object to `properties` in `terraform.tfvars`, then run `terraform plan`.
