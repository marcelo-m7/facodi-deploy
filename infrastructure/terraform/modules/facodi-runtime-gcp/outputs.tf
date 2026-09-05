output "service_name" {
  value = try(google_cloud_run_v2_service.odoo[0].name, null)
}

output "service_uri" {
  value = try(google_cloud_run_v2_service.odoo[0].uri, null)
}

output "migration_job_name" {
  value = try(google_cloud_run_v2_job.migrate[0].name, null)
}

output "database_instance_name" {
  value = google_sql_database_instance.main.name
}

output "database_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "database_name" {
  value = google_sql_database.odoo.name
}

output "runtime_service_account" {
  value = google_service_account.runtime.email
}

output "filestore_bucket" {
  value = google_storage_bucket.filestore.name
}

output "db_password_secret" {
  value = google_secret_manager_secret.db_password.secret_id
}

output "admin_password_secret" {
  value = google_secret_manager_secret.admin_password.secret_id
}
