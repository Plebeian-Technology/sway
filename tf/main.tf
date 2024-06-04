provider "google" {
  project = var.project
  region  = var.region

  default_labels = {
      environment = var.environment
      terraform   = "true"
  }
}

provider "digitalocean" {
  token             = var.digitalocean_token

  spaces_access_id  = var.digitalocean_spaces_access_id
  spaces_secret_key = var.digitalocean_spaces_secret_key
}

module "secrets" {
  source = "./modules/secrets"

  project = var.project
  region  = var.region
  environment = var.environment

  digitalocean_spaces_access_id = var.digitalocean_spaces_access_id
  digitalocean_spaces_secret_key = var.digitalocean_spaces_secret_key
}

module "iam" {
  count = var.environment == "prod" ? 1 : 0

  source = "./modules/iam"

  project = var.project
  region  = var.region
  environment = var.environment
}

module "buckets" {
  source = "./modules/buckets"

  project = var.project
  region  = var.region
  environment = var.environment
}

module "backup" {
  source = "./modules/backup"

  providers = {
    digitalocean = digitalocean
  }

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
