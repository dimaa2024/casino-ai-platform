variable "organization_context" {
  description = "Shared context used by all property cells"
  type = object({
    bootstrap_project = string
    default_region    = string
    labels            = map(string)
  })
}

variable "properties" {
  description = "Property cell definitions keyed by a short property code"
  type = map(object({
    property_id              = string
    project_id               = string
    region                   = string
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
  }))
}
