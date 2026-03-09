output "project_id" {
  value = var.property.project_id
}

output "region" {
  value = var.property.region
}

output "network" {
  value = google_compute_network.cell.name
}

output "subnet" {
  value = google_compute_subnetwork.cell.name
}

output "kms_key" {
  value = google_kms_crypto_key.cell.id
}

output "player_events_topic" {
  value = google_pubsub_topic.player_events.id
}

output "ops_events_topic" {
  value = google_pubsub_topic.ops_events.id
}

output "player_api_service_url" {
  value = google_cloud_run_v2_service.player_api.uri
}

output "processor_service_url" {
  value = google_cloud_run_v2_service.message_processor.uri
}

output "billing_worker_service_url" {
  value = google_cloud_run_v2_service.billing_worker.uri
}

output "service_accounts" {
  value = {
    player_api        = google_service_account.player_api.email
    message_processor = google_service_account.message_processor.email
    billing_worker    = google_service_account.billing_worker.email
  }
}
