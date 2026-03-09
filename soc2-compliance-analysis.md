# SOC 2 Compliance Analysis - Casino Property Cell Architecture

## Architecture summary
The Terraform design uses a cell-based model where each casino property receives an isolated deployment boundary.
A property cell contains a dedicated VPC subnet, dedicated service accounts, dedicated encryption key, dedicated Cloud SQL instance, and dedicated messaging resources.

This implementation supports both:
- single-project multi-cell deployment for demonstration and fast onboarding
- per-project cell isolation for stronger production-grade segregation

## How this supports SOC 2

### Logical access controls (CC6)
- Dedicated service accounts per workload (`player-api`, `message-processor`, `billing-worker`).
- IAM grants are scoped to least privilege by service function.
- Secrets are separated and bound with resource-level IAM.
- Administrative access is explicit via `allowed_admin_principals`.

### System operations and change management (CC7)
- Infrastructure is managed as code via Terraform.
- Changes are reviewable in Git history and pull requests.
- Reproducible plans reduce undocumented infrastructure drift.

### Risk mitigation and data protection (CC8 + Confidentiality)
- Encryption at rest with per-property customer-managed keys (CMEK).
- Cloud SQL and Pub/Sub are bound to property-specific keys.
- Private networking for Cloud SQL and serverless egress control.
- Cell boundaries reduce blast radius and cross-tenant data exposure risk.

## Controls addressed by this design
- Tenant isolation pattern.
- Least privilege IAM model.
- Encryption key segregation.
- Secrets segregation.
- Deterministic provisioning and auditability of infra changes.

## Controls partially addressed or not addressed
- Centralized SIEM correlation and SOC alert response workflows.
- Formal vulnerability management and patch SLAs.
- Full incident response playbooks and evidence of regular tabletop exercises.
- Business continuity/disaster recovery test evidence (RTO/RPO validation).
- Endpoint/device management controls for workforce systems.
- Vendor risk management process and third-party due diligence evidence.
- Formal policy governance lifecycle (approval, exception tracking, attestation).

## What to add for production SOC 2 audit readiness
- Separate GCP project per property for hard tenant boundary.
- Organization policies to enforce guardrails (no public IP SQL, allowed regions, CMEK required).
- Centralized audit logging export to immutable storage + SIEM.
- Security Command Center, alerting pipelines, on-call response runbooks.
- Key lifecycle policy and formal key rotation evidence.
- Backup and restore tests with documented outcomes.
- CI/CD controls: mandatory approvals, policy-as-code checks, signed artifacts.
- Regular access recertification and privileged access reviews.
- Data classification policy mapped to retention/deletion automation.

## Evidence artifacts this design can produce
- Terraform plans/applies and Git commit history.
- IAM policy bindings by service account and resource.
- KMS key IAM and rotation settings.
- Audit logs for admin and data access events.
- Cloud SQL and Pub/Sub encryption configuration snapshots.

## Residual risk statement
This implementation is a strong foundation for SOC 2 Security and Confidentiality criteria but does not, by itself, satisfy all organizational and operational controls required for an external audit.
