locals {
  bucket_name = var.environment == "prod" ? "sway-sqlite" : "${var.environment}-sway-sqlite"
}

resource "google_cloud_run_service" "app" {
  provider = google-beta

  name                       = var.environment == "prod" ? "sway" : "sway-${var.environment}"
  location                   = "us-central1"
  autogenerate_revision_name = false

  template {
    spec {
      # 0 thread-safe, the system should manage the max concurrency. This is the default value.
      container_concurrency = 0

      containers {
        name  = "sway-1"
        image = "us-central1-docker.pkg.dev/sway-421916/sway/sway:latest"

        # PUBLIC ENV VARS

        env {
          name  = "RAILS_ENV"
          value = "production"
        }

        # SECRET ENV VARS

        env {
          name = "ADMIN_PHONES"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "ADMIN_PHONES"
            }
          }
        }
        env {
          name = "GOOGLE_MAPS_API_KEY"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "GOOGLE_MAPS_API_KEY"
            }
          }
        }
        env {
          name = "GOOGLE_RECAPTCHA_SECRET_KEY"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "GOOGLE_RECAPTCHA_SECRET_KEY"
            }
          }
        }
        env {
          name = "SECRET_KEY_BASE"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "SECRET_KEY_BASE"
            }
          }
        }
        env {
          name = "SWAY_DATABASE_PASSWORD"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "SWAY_DATABASE_PASSWORD"
            }
          }
        }
        env {
          name = "TWILIO_ACCOUNT_SID"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "TWILIO_ACCOUNT_SID"
            }
          }
        }
        env {
          name = "TWILIO_AUTH_TOKEN"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "TWILIO_AUTH_TOKEN"
            }
          }
        }
        env {
          name = "TWILIO_VERIFY_SERVICE_SID"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "TWILIO_VERIFY_SERVICE_SID"
            }
          }
        }
        env {
          name = "VAPID_PRIVATE_KEY"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "VAPID_PRIVATE_KEY"
            }
          }
        }
        env {
          name = "VAPID_PUBLIC_KEY"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "VAPID_PUBLIC_KEY"
            }
          }
        }
        env {
          name = "VITE_GOOGLE_MAPS_API_KEY"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "VITE_GOOGLE_MAPS_API_KEY"
            }
          }
        }
        env {
          name = "VITE_GOOGLE_RECAPTCHA_SITE_KEY"
          value_from {
            secret_key_ref {
              key  = "latest"
              name = "VITE_GOOGLE_RECAPTCHA_SITE_KEY"
            }
          }
        }

        startup_probe {
          initial_delay_seconds = 0
          timeout_seconds       = 240
          period_seconds        = 240
          failure_threshold     = 1

          tcp_socket {
            port = 3000
          }
        }

        liveness_probe {
          failure_threshold = 9
          http_get {
            path = "/up"
            port = "3000"
          }
        }

        volume_mounts {
          name       = local.bucket_name
          mount_path = "/rails/storage"
        }

        ports {
          name           = "http1" # default, use h2c for http/2
          container_port = "3000"
        }

        resources {
          limits = {
            cpu : "1000m",
            memory : "512Mi"
          }
        }
      }

      volumes {
        name = local.bucket_name

        csi {
          driver    = "gcsfuse.run.googleapis.com"
          read_only = false
          volume_attributes = {
            "bucketName" = local.bucket_name
          }
        }
      }
    }
  }

  metadata {
    annotations = {
      "run.googleapis.com/execution-environment" : "gen2",
      "run.googleapis.com/launch-stage" : "BETA"
    }

    labels = {
      environment = var.environment
      terraform   = true
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.app.location
  project  = google_cloud_run_service.app.project
  service  = google_cloud_run_service.app.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

resource "google_cloud_run_domain_mapping" "app" {
  name     = "${var.environment == "prod" ? "app" : var.environment}.sway.vote"
  location = "us-central1"
  project  = var.project

  metadata {
    namespace = var.project
  }

  spec {
    route_name       = var.environment == "prod" ? "sway" : "sway-${var.environment}"
    force_override   = false
    certificate_mode = "AUTOMATIC"
  }
}


# BACKUP

resource "google_cloud_run_v2_job" "backup" {
  provider = google-beta

  name     = "${var.environment}-sqlite-backup"
  location = var.region
  project  = var.project

  launch_stage = "BETA"

  template {

    task_count = 1
    parallelism = 1

    template {
      execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

      containers {
        image = "litestream/litestream"

        command = [
          "litestream",
          "replicate",
          "${var.environment == "prod" ? "production" : var.environment}.db",
          "https://${local.bucket_name}-backup.nyc3.digitaloceanspaces.com/${var.environment}.db"
        ]

        env {
          name = "SWAY_DATABASE_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = var.secrets.SWAY_DATABASE_PASSWORD
              version = "latest"
            }
          }
        }

        resources {
          limits = {
            cpu    = "512Mi"
            memory = "512Mi"
          }
        }

        volume_mounts {
          name       = local.bucket_name
          mount_path = "/data/db"
        }

      }

      volumes {
        name = local.bucket_name

        gcs {
          bucket    = local.bucket_name
          read_only = true
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      launch_stage,
    ]
  }
}
