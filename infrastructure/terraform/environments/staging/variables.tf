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

variable "min_instances" {
  description = "Minimum staging Cloud Run instances. Use 1 during cron/background acceptance tests."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1], var.min_instances)
    error_message = "staging min_instances must be 0 or 1"
  }
}

variable "database_tier" {
  type    = string
  default = "db-custom-1-3840"
}
