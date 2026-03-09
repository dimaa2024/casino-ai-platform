variable "organization_context" {
  description = "Shared metadata for all cells"
  type = object({
    labels = map(string)
  })
}

variable "property" {
  description = "Single property cell configuration"
  type = object({
    property_id              = string
    project_id               = string
    region                   = string
    kms_key_ring_name        = optional(string)
    vpc_cidr                 = string
    connector_cidr           = string
    cloud_sql_tier           = string
    db_name                  = string
    db_user                  = string
    pubsub_message_retention = string
    allowed_admin_principals = list(string)
    cloud_run_player_api_cpu = string
    cloud_run_player_api_mem = string
    cloud_run_processor_cpu  = string
    cloud_run_processor_mem  = string
    cloud_run_billing_cpu    = string
    cloud_run_billing_mem    = string
  })
}
