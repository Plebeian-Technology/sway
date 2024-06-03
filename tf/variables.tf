variable "environment" {
  default = "prod"
}

variable "project" {
  default = "sway-421916"
}

variable "region" {
  default = "us-central1"
}

variable "digitalocean_token" {
  type      = string
  sensitive = true
}
variable "digitalocean_spaces_access_id" {
  type      = string
  sensitive = true
}
variable "digitalocean_spaces_secret_key" {
  type      = string
  sensitive = true
}
