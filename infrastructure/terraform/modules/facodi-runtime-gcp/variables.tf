variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production"
  }
}

variable "initial_image_uri" {
  type = string
}

variable "runtime_enabled" {
  type    = bool
  default = false
}

variable "public_access_enabled" {
  type    = bool
  default = false
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 1

  validation {
    condition     = var.max_instances == 1
    error_message = "runtime v1 requires max_instances = 1"
  }
}

variable "database_tier" {
  type    = string
  default = "db-custom-1-3840"
}

variable "database_availability_type" {
  type    = string
  default = "ZONAL"
}

variable "container_cpu" {
  type    = string
  default = "1"
}

variable "container_memory" {
  type    = string
  default = "2Gi"
}

variable "deploy_service_account_email" {
  type = string
}
