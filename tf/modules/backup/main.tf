

########################################################################
# DIGITAL OCEAN SQLITE BACKUP
########################################################################

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
    allowed_methods = ["GET", "PUT", "POST", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}
