output "artifact_repository" {
  value = google_artifact_registry_repository.facodi.repository_id
}

output "deploy_service_account" {
  value = google_service_account.deploy.email
}

output "image_repository_prefix" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.facodi.repository_id}/odoo"
}
