
##############################################################################################################
# Created via TF
##############################################################################################################

resource "google_secret_manager_secret" "LITESTREAM_ACCESS_KEY_ID" {
  secret_id = "LITESTREAM_ACCESS_KEY_ID"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "LITESTREAM_ACCESS_KEY_ID" {
  secret = google_secret_manager_secret.LITESTREAM_ACCESS_KEY_ID.id
  secret_data = var.digitalocean_spaces_access_id
}

##############################

resource "google_secret_manager_secret" "LITESTREAM_SECRET_ACCESS_KEY" {
  secret_id = "LITESTREAM_SECRET_ACCESS_KEY"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "LITESTREAM_SECRET_ACCESS_KEY" {
  secret = google_secret_manager_secret.LITESTREAM_SECRET_ACCESS_KEY.id
  secret_data = var.digitalocean_spaces_secret_key
}

##############################################################################################################
# Created via console and imported into Terraform
##############################################################################################################

resource "google_secret_manager_secret" "ADMIN_PHONES" {
  secret_id = "ADMIN_PHONES"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "GOOGLE_MAPS_API_KEY" {
  secret_id = "GOOGLE_MAPS_API_KEY"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "GOOGLE_RECAPTCHA_SECRET_KEY" {
  secret_id = "GOOGLE_RECAPTCHA_SECRET_KEY"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "SECRET_KEY_BASE" {
  secret_id = "SECRET_KEY_BASE"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "SWAY_DATABASE_PASSWORD" {
  secret_id = "SWAY_DATABASE_PASSWORD"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "TWILIO_ACCOUNT_SID" {
  secret_id = "TWILIO_ACCOUNT_SID"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "TWILIO_AUTH_TOKEN" {
  secret_id = "TWILIO_AUTH_TOKEN"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "TWILIO_VERIFY_SERVICE_SID" {
  secret_id = "TWILIO_VERIFY_SERVICE_SID"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "VAPID_PRIVATE_KEY" {
  secret_id = "VAPID_PRIVATE_KEY"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "VAPID_PUBLIC_KEY" {
  secret_id = "VAPID_PUBLIC_KEY"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "VITE_GOOGLE_MAPS_API_KEY" {
  secret_id = "VITE_GOOGLE_MAPS_API_KEY"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "VITE_GOOGLE_RECAPTCHA_SITE_KEY" {
  secret_id = "VITE_GOOGLE_RECAPTCHA_SITE_KEY"
  replication {
    auto {}
  }
}
