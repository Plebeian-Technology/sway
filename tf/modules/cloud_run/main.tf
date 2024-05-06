resource "google_cloud_run_service" "default" {
  name     = "sway"
  location = "us-central1"

  autogenerate_revision_name = true

  template {

    spec {
        # 0 - thread-safe, the system should manage the max concurrency. This is the default value.
        container_concurrency = 0

      containers {
        image = "us-central1-docker.pkg.dev/sway-421916/sway/sway:latest"


        startup_probe {
          initial_delay_seconds = 0
          timeout_seconds       = 1
          period_seconds        = 9
          failure_threshold     = 1
          tcp_socket {
            port = 3000
          }
        }
        liveness_probe {
          http_get {
            path = "/up"
            port = "3000"
          }
        }

        volume_mounts {
          name = "sway-sqlite"
          mount_path = "/rails/storage"
          }

          ports {
            name = "http1" # default, use h2c for http/2
            protocol = "tcp"
            container_port = "3000"
          }

          env {
            value_from {
              secret_key_ref {
                key = "latest"
                name = 
              }
            }
          }

          # resources {
          #   limits = 
          #   requests = 
          # }
      }


      volumes {
        name = "sway-sqlite"
      }
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
  location = google_cloud_run_service.default.location
  project  = google_cloud_run_service.default.project
  service  = google_cloud_run_service.default.name

  policy_data = data.google_iam_policy.noauth.policy_data
}
