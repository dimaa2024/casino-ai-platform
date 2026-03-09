output "cells" {
  description = "Property cell output summary"
  value = {
    for k, v in module.property_cell :
    k => {
      project_id                 = v.project_id
      region                     = v.region
      network                    = v.network
      subnet                     = v.subnet
      kms_key                    = v.kms_key
      player_api_service_url     = v.player_api_service_url
      processor_service_url      = v.processor_service_url
      billing_worker_service_url = v.billing_worker_service_url
      player_events_topic        = v.player_events_topic
      ops_events_topic           = v.ops_events_topic
    }
  }
}
