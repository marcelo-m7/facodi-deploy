provider "google" {
  project = var.project_id
  region  = var.region
}

module "runtime" {
  source = "../../modules/facodi-runtime-gcp"

  project_id                   = var.project_id
  region                       = var.region
  environment                  = "staging"
  runtime_enabled              = var.runtime_enabled
  public_access_enabled        = var.public_access_enabled
  initial_image_uri            = var.initial_image_uri
  min_instances                = 0
  max_instances                = 1
  database_tier                = var.database_tier
  deploy_service_account_email = "facodi-github-deploy@${var.project_id}.iam.gserviceaccount.com"
}
