output "service_name" {
  value = module.runtime.service_name
}

output "service_uri" {
  value = module.runtime.service_uri
}

output "migration_job_name" {
  value = module.runtime.migration_job_name
}

output "database_connection_name" {
  value = module.runtime.database_connection_name
}

output "filestore_bucket" {
  value = module.runtime.filestore_bucket
}

output "runtime_service_account" {
  value = module.runtime.runtime_service_account
}
