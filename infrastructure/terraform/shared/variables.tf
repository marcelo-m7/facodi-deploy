variable "project_id" {
  type    = string
  default = "marcelo-497411"
}

variable "region" {
  type    = string
  default = "europe-southwest1"
}

variable "github_repository" {
  type    = string
  default = "marcelo-m7/facodi-deploy"
}

variable "workload_identity_pool_id" {
  type    = string
  default = "github"
}

variable "artifact_repository" {
  type    = string
  default = "facodi"
}
