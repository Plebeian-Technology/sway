########################################################################
# GOOGLE CLOUD SQLITE
########################################################################

resource "google_storage_bucket" "assets" {
  name     = var.environment == "prod" ? "sway-assets" : "${var.environment}-sway-assets"
  location = var.region

  public_access_prevention = "inherited"

  cors {
    max_age_seconds = 3600
    method = [
      "GET",
      "PUT",
    ]
    origin = [
      "https://localhost:3000",
      "https://app.sway.vote",
    ]
    response_header = [
      "Content-Type",
      "x-goog-resumable",
    ]
  }
}

resource "google_storage_bucket" "sqlite" {
  name     = var.environment == "prod" ? "sway-sqlite" : "${var.environment}-sway-sqlite"
  location = var.region

  public_access_prevention = "enforced"
}

########################################################################
# TERRAFORM BUCKET
########################################################################

data "google_storage_bucket" "terraform" {
  name = "sway-terraform"
}
