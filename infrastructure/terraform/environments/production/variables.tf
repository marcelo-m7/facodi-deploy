variable "project_id" {
  type    = string
  default = "marcelo-497411"
}

variable "region" {
  type    = string
  default = "europe-southwest1"
}

variable "runtime_enabled" {
  type    = bool
  default = false
}

variable "public_access_enabled" {
  type    = bool
  default = false
}

variable "initial_image_uri" {
  type    = string
  default = ""

  validation {
    condition     = !var.runtime_enabled || length(trimspace(var.initial_image_uri)) > 0
    error_message = "initial_image_uri must be non-empty when runtime_enabled is true"
  }
}

variable "database_tier" {
  type    = string
  default = "db-custom-1-3840"
}
