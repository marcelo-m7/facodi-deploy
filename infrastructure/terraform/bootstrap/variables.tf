variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
  default     = "marcelo-497411"
}

variable "region" {
  description = "Primary Google Cloud region."
  type        = string
  default     = "europe-southwest1"
}

variable "state_bucket_name" {
  description = "GCS bucket used for Terraform remote state."
  type        = string
  default     = "marcelo-497411-facodi-tfstate"
}

variable "github_repository" {
  description = "GitHub repository allowed to federate into Google Cloud."
  type        = string
  default     = "marcelo-m7/facodi-deploy"
}

variable "workload_identity_pool_id" {
  type    = string
  default = "github"
}

variable "workload_identity_provider_id" {
  type    = string
  default = "facodi-deploy"
}
