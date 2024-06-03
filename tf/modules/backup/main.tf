

########################################################################
# DIGITAL OCEAN SQLITE BACKUP
########################################################################

provider "digitalocean" {
  token             = var.digitalocean_token

  spaces_access_id  = var.digitalocean_spaces_access_id
  spaces_secret_key = var.digitalocean_spaces_secret_key
}

resource "digitalocean_spaces_bucket" "sqlite" {
  provider = digitalocean

  name   = "${var.environment}-sway-sqlite-backup"
  region = "nyc3"

  acl = "private"
}

resource "digitalocean_spaces_bucket_cors_configuration" "test" {
  bucket = digitalocean_spaces_bucket.sqlite.id
  region = "nyc3"

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["${var.environment == "prod" ? "app" : var.environment}.sway.vote"]
    max_age_seconds = 3000
  }
}
