variable "region" {}
variable "project" {}
variable "environment" {}

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
