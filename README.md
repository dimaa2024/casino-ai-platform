# Casino AI Platform - Property Cell Terraform (GCP)

This repository implements a cell-based infrastructure pattern for casino hospitality on GCP.
Each property cell is isolated with its own network, service identities, data resources, and encryption key.
This is intentionally not the full platform: it delivers one representative property cell with real compute, database, messaging/eventing, IAM roles, and encryption so isolation and least-privilege behavior can be demonstrated in practice.
The Terraform is runnable with `terraform plan` and `terraform apply`.

## Implemented cell components
- Isolated VPC and subnet per property.
- Private Service Access + Serverless VPC connector.
- Per-property CMEK key (Cloud KMS).
- Cloud SQL PostgreSQL (private IP, CMEK).
- Pub/Sub topics/subscription (CMEK).
- Three Cloud Run services with separate service accounts:
  - `player-api`
  - `message-processor`
  - `billing-worker`
- Least-privilege IAM scoped by service responsibility.
- Secrets in Secret Manager with scoped access.

## Repository layout
- `infra/environments/properties`: runnable Terraform entrypoint.
- `infra/modules/property_cell`: reusable property cell module.
- `soc2-compliance-analysis.md`: SOC 2 analysis for this architecture.

## GCP project
This stack is configured to run in:
- `casino-ai-platform`

Update `infra/environments/properties/terraform.tfvars` if you want different project IDs per property.

## Run Terraform
```bash
cd /Users/da/code/casino-ai-platform/infra/environments/properties
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
```

To create resources:
```bash
terraform apply
```

## Add a new property with minimal configuration
1. Open `infra/environments/properties/terraform.tfvars`.
2. Add one new object under `properties`.
3. Set unique values for:
   - `property_id`
   - `vpc_cidr`
   - `connector_cidr`
   - `project_id` (same or separate project)
4. Run `terraform plan` and `terraform apply`.

No module code changes are required.

## IAM isolation demonstration
- `message-processor` can read player event subscription and publish ops events.
- `message-processor` cannot access billing secret.
- `billing-worker` can read billing secret.
- `billing-worker` cannot read DB password unless explicitly granted.

## Notes
- Two properties are included in `terraform.tfvars.example` to demonstrate additive provisioning.
- For strictest regulatory isolation, use a dedicated GCP project per property cell.
