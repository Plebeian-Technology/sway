variable "region" {}
variable "project" {}
variable "environment" {}

variable "secrets" {
  type = map(string)
  sensitive = true
}