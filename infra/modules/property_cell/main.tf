locals {
  name_prefix = replace(var.property.property_id, "_", "-")
  key_ring_name = (
    try(var.property.kms_key_ring_name, null) != null && trimspace(var.property.kms_key_ring_name) != ""
    ? var.property.kms_key_ring_name
    : "${local.name_prefix}-kr"
  )

  labels = merge(var.organization_context.labels, {
    property = var.property.property_id
    managed  = "terraform"
  })

  required_services = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com"
  ])

  admin_roles = toset([
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/pubsub.admin",
    "roles/secretmanager.admin",
    "roles/cloudkms.admin",
    "roles/iam.serviceAccountUser"
  ])

  admin_bindings = {
    for pair in flatten([
      for principal in var.property.allowed_admin_principals : [
        for role in local.admin_roles : {
          key       = "${principal}|${role}"
          principal = principal
          role      = role
        }
      ]
    ]) : pair.key => pair
  }
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.property.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service_identity" "cloudsql" {
  provider = google-beta
  project  = var.property.project_id
  service  = "sqladmin.googleapis.com"

  depends_on = [google_project_service.required]
}

resource "google_project_service_identity" "pubsub" {
  provider = google-beta
  project  = var.property.project_id
  service  = "pubsub.googleapis.com"

  depends_on = [google_project_service.required]
}

resource "time_sleep" "wait_for_cloudsql_service_agent" {
  depends_on      = [google_project_service_identity.cloudsql]
  create_duration = "45s"
}

resource "time_sleep" "wait_for_pubsub_service_agent" {
  depends_on      = [google_project_service_identity.pubsub]
  create_duration = "20s"
}

resource "google_compute_network" "cell" {
  project                 = var.property.project_id
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "cell" {
  project                  = var.property.project_id
  name                     = "${local.name_prefix}-subnet"
  ip_cidr_range            = var.property.vpc_cidr
  region                   = var.property.region
  network                  = google_compute_network.cell.id
  private_ip_google_access = true
}

resource "google_compute_firewall" "allow_internal" {
  project = var.property.project_id
  name    = "${local.name_prefix}-allow-internal"
  network = google_compute_network.cell.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.property.vpc_cidr]
}

resource "google_compute_global_address" "private_service_range" {
  project       = var.property.project_id
  name          = "${local.name_prefix}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.cell.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.cell.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

resource "google_vpc_access_connector" "serverless" {
  project       = var.property.project_id
  region        = var.property.region
  name          = "${local.name_prefix}-connector"
  ip_cidr_range = var.property.connector_cidr
  network       = google_compute_network.cell.name

  depends_on = [google_project_service.required]
}

resource "google_kms_key_ring" "cell" {
  project  = var.property.project_id
  name     = local.key_ring_name
  location = var.property.region
}

resource "google_kms_crypto_key" "cell" {
  name            = "${local.name_prefix}-cmek"
  key_ring        = google_kms_key_ring.cell.id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key_iam_member" "cloudsql_key_user" {
  crypto_key_id = google_kms_crypto_key.cell.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.cloudsql.email}"

  depends_on = [time_sleep.wait_for_cloudsql_service_agent]
}

resource "google_kms_crypto_key_iam_member" "pubsub_key_user" {
  crypto_key_id = google_kms_crypto_key.cell.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.pubsub.email}"

  depends_on = [time_sleep.wait_for_pubsub_service_agent]
}

resource "google_service_account" "player_api" {
  project      = var.property.project_id
  account_id   = "${substr(replace(local.name_prefix, "-", ""), 0, 18)}-player"
  display_name = "${var.property.property_id} player api"
}

resource "google_service_account" "message_processor" {
  project      = var.property.project_id
  account_id   = "${substr(replace(local.name_prefix, "-", ""), 0, 14)}-processor"
  display_name = "${var.property.property_id} message processor"
}

resource "google_service_account" "billing_worker" {
  project      = var.property.project_id
  account_id   = "${substr(replace(local.name_prefix, "-", ""), 0, 16)}-billing"
  display_name = "${var.property.property_id} billing worker"
}

resource "google_sql_database_instance" "cell" {
  project             = var.property.project_id
  name                = "${local.name_prefix}-pg"
  database_version    = "POSTGRES_15"
  region              = var.property.region
  deletion_protection = false

  settings {
    tier              = var.property.cloud_sql_tier
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.cell.id
    }

    backup_configuration {
      enabled = true
    }

    disk_autoresize = true
    disk_type       = "PD_SSD"

    location_preference {
      zone = "${var.property.region}-a"
    }
  }

  encryption_key_name = google_kms_crypto_key.cell.id

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_kms_crypto_key_iam_member.cloudsql_key_user
  ]
}

resource "google_sql_database" "app" {
  project  = var.property.project_id
  instance = google_sql_database_instance.cell.name
  name     = var.property.db_name
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "google_sql_user" "app" {
  project  = var.property.project_id
  instance = google_sql_database_instance.cell.name
  name     = var.property.db_user
  password = random_password.db_password.result
}

resource "google_secret_manager_secret" "db_password" {
  project   = var.property.project_id
  secret_id = "${local.name_prefix}-db-password"

  replication {
    user_managed {
      replicas {
        location = var.property.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "random_password" "billing_api_key" {
  length  = 40
  special = false
}

resource "google_secret_manager_secret" "billing_api_key" {
  project   = var.property.project_id
  secret_id = "${local.name_prefix}-billing-api-key"

  replication {
    user_managed {
      replicas {
        location = var.property.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "billing_api_key" {
  secret      = google_secret_manager_secret.billing_api_key.id
  secret_data = random_password.billing_api_key.result
}

resource "google_pubsub_topic" "player_events" {
  project                    = var.property.project_id
  name                       = "${local.name_prefix}-player-events"
  kms_key_name               = google_kms_crypto_key.cell.id
  message_retention_duration = var.property.pubsub_message_retention

  depends_on = [google_kms_crypto_key_iam_member.pubsub_key_user]
}

resource "google_pubsub_topic" "ops_events" {
  project                    = var.property.project_id
  name                       = "${local.name_prefix}-ops-events"
  kms_key_name               = google_kms_crypto_key.cell.id
  message_retention_duration = var.property.pubsub_message_retention

  depends_on = [google_kms_crypto_key_iam_member.pubsub_key_user]
}

resource "google_pubsub_subscription" "processor" {
  project                    = var.property.project_id
  name                       = "${local.name_prefix}-processor-sub"
  topic                      = google_pubsub_topic.player_events.name
  message_retention_duration = var.property.pubsub_message_retention
}

resource "google_project_iam_member" "player_cloudsql_client" {
  project = var.property.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.player_api.email}"
}

resource "google_project_iam_member" "processor_cloudsql_client" {
  project = var.property.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.message_processor.email}"
}

resource "google_pubsub_topic_iam_member" "player_publish_player_events" {
  project = var.property.project_id
  topic   = google_pubsub_topic.player_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.player_api.email}"
}

resource "google_pubsub_subscription_iam_member" "processor_subscriber" {
  project      = var.property.project_id
  subscription = google_pubsub_subscription.processor.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.message_processor.email}"
}

resource "google_pubsub_topic_iam_member" "processor_publish_ops" {
  project = var.property.project_id
  topic   = google_pubsub_topic.ops_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.message_processor.email}"
}

resource "google_secret_manager_secret_iam_member" "player_db_secret_access" {
  project   = var.property.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.player_api.email}"
}

resource "google_secret_manager_secret_iam_member" "processor_db_secret_access" {
  project   = var.property.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.message_processor.email}"
}

resource "google_secret_manager_secret_iam_member" "billing_secret_access" {
  project   = var.property.project_id
  secret_id = google_secret_manager_secret.billing_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.billing_worker.email}"
}

resource "google_project_iam_member" "admins" {
  for_each = local.admin_bindings

  project = var.property.project_id
  role    = each.value.role
  member  = each.value.principal
}

resource "google_cloud_run_v2_service" "player_api" {
  project  = var.property.project_id
  name     = "${local.name_prefix}-player-api"
  location = var.property.region

  template {
    service_account = google_service_account.player_api.email

    vpc_access {
      connector = google_vpc_access_connector.serverless.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      env {
        name  = "PROPERTY_ID"
        value = var.property.property_id
      }

      env {
        name  = "DB_INSTANCE"
        value = google_sql_database_instance.cell.connection_name
      }

      env {
        name  = "DB_NAME"
        value = var.property.db_name
      }

      env {
        name  = "PLAYER_EVENTS_TOPIC"
        value = google_pubsub_topic.player_events.name
      }

      resources {
        limits = {
          cpu    = var.property.cloud_run_player_api_cpu
          memory = var.property.cloud_run_player_api_mem
        }
      }
    }
  }

  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  depends_on = [
    google_project_iam_member.player_cloudsql_client,
    google_pubsub_topic_iam_member.player_publish_player_events,
    google_secret_manager_secret_iam_member.player_db_secret_access
  ]
}

resource "google_cloud_run_v2_service" "message_processor" {
  project  = var.property.project_id
  name     = "${local.name_prefix}-processor"
  location = var.property.region

  template {
    service_account = google_service_account.message_processor.email

    vpc_access {
      connector = google_vpc_access_connector.serverless.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      env {
        name  = "PROPERTY_ID"
        value = var.property.property_id
      }

      env {
        name  = "PLAYER_SUBSCRIPTION"
        value = google_pubsub_subscription.processor.name
      }

      env {
        name  = "OPS_TOPIC"
        value = google_pubsub_topic.ops_events.name
      }

      env {
        name  = "DB_INSTANCE"
        value = google_sql_database_instance.cell.connection_name
      }

      resources {
        limits = {
          cpu    = var.property.cloud_run_processor_cpu
          memory = var.property.cloud_run_processor_mem
        }
      }
    }
  }

  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  depends_on = [
    google_project_iam_member.processor_cloudsql_client,
    google_pubsub_subscription_iam_member.processor_subscriber,
    google_pubsub_topic_iam_member.processor_publish_ops,
    google_secret_manager_secret_iam_member.processor_db_secret_access
  ]
}

resource "google_cloud_run_v2_service" "billing_worker" {
  project  = var.property.project_id
  name     = "${local.name_prefix}-billing-worker"
  location = var.property.region

  template {
    service_account = google_service_account.billing_worker.email

    vpc_access {
      connector = google_vpc_access_connector.serverless.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      env {
        name  = "PROPERTY_ID"
        value = var.property.property_id
      }

      env {
        name  = "BILLING_SECRET"
        value = google_secret_manager_secret.billing_api_key.secret_id
      }

      resources {
        limits = {
          cpu    = var.property.cloud_run_billing_cpu
          memory = var.property.cloud_run_billing_mem
        }
      }
    }
  }

  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  depends_on = [google_secret_manager_secret_iam_member.billing_secret_access]
}
