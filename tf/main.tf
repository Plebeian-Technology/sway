provider "google" {
  project = var.project
  region  = var.region

  default_labels = {
      environment = var.environment
      terraform   = "true"
  }
}

module "secrets" {
  source = "./modules/secrets"

  project = var.project
  region  = var.region
  environment = var.environment

  digitalocean_spaces_access_id = var.digitalocean_spaces_access_id
  digitalocean_spaces_secret_key = var.digitalocean_spaces_secret_key
}

module "buckets" {
  source = "./modules/buckets"

  project = var.project
  region  = var.region
  environment = var.environment
}

module "backup" {
  source = "./modules/backup"

  project = var.project
  region  = var.region
  environment = var.environment

  digitalocean_token = var.digitalocean_token
  digitalocean_spaces_access_id = var.digitalocean_spaces_access_id
  digitalocean_spaces_secret_key = var.digitalocean_spaces_secret_key
}

module "cloud_run" {
  source = "./modules/cloud_run"

  project = var.project
  region  = var.region
  environment = var.environment

  secrets = module.secrets.secrets
}
