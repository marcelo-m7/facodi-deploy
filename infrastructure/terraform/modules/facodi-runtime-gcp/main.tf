locals {
  prefix             = "facodi-${var.environment}"
  database_name      = "facodi_${var.environment}"
  runtime_account_id = "facodi-${var.environment}-runtime"
  filestore_bucket   = "${var.project_id}-facodi-${var.environment}-filestore"
  db_secret_id       = "facodi-${var.environment}-db-password"
  admin_secret_id    = "facodi-${var.environment}-admin-passwd"
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = local.runtime_account_id
  display_name = "FACODI ${var.environment} runtime"
}

resource "google_project_iam_member" "runtime_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_service_account_iam_member" "deploy_act_as_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deploy_service_account_email}"
}

resource "google_storage_bucket" "filestore" {
  name                        = local.filestore_bucket
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_member" "runtime_filestore" {
  bucket = google_storage_bucket.filestore.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = local.db_secret_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "admin_password" {
  project   = var.project_id
  secret_id = local.admin_secret_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "runtime_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "runtime_admin_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.admin_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_sql_database_instance" "main" {
  project             = var.project_id
  name                = "${local.prefix}-pg"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = var.environment == "production"

  settings {
    tier                        = var.database_tier
    edition                     = "ENTERPRISE"
    availability_type           = var.database_availability_type
    disk_autoresize             = true
    deletion_protection_enabled = var.environment == "production"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }
}

resource "google_sql_database" "odoo" {
  project  = var.project_id
  name     = local.database_name
  instance = google_sql_database_instance.main.name
}

resource "google_cloud_run_v2_service" "odoo" {
  count               = var.runtime_enabled ? 1 : 0
  project             = var.project_id
  name                = local.prefix
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = var.environment == "production"

  template {
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    service_account       = google_service_account.runtime.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      name  = "odoo"
      image = var.initial_image_uri

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.container_cpu
          memory = var.container_memory
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }

      env {
        name  = "DB_HOST"
        value = "/cloudsql/${google_sql_database_instance.main.connection_name}"
      }
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_USER"
        value = "odoo"
      }
      env {
        name  = "ODOO_DB"
        value = google_sql_database.odoo.name
      }
      env {
        name  = "FACODI_MODULES"
        value = "facodi_learning,website_facodi"
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "ODOO_ADMIN_PASSWD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.admin_password.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
      volume_mounts {
        name       = "filestore"
        mount_path = "/var/lib/odoo/filestore"
      }
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    volumes {
      name = "filestore"
      gcs {
        bucket        = google_storage_bucket.filestore.name
        read_only     = false
        mount_options = ["implicit-dirs", "file-mode=0666", "dir-mode=0777"]
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  depends_on = [
    google_project_iam_member.runtime_cloudsql,
    google_storage_bucket_iam_member.runtime_filestore,
    google_secret_manager_secret_iam_member.runtime_db_password,
    google_secret_manager_secret_iam_member.runtime_admin_password,
  ]
}

resource "google_cloud_run_v2_job" "migrate" {
  count               = var.runtime_enabled ? 1 : 0
  project             = var.project_id
  name                = "${local.prefix}-migrate"
  location            = var.region
  deletion_protection = var.environment == "production"

  template {
    task_count  = 1
    parallelism = 1

    template {
      execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
      service_account       = google_service_account.runtime.email
      timeout               = "1800s"
      max_retries           = 0

      containers {
        name  = "migrate"
        image = var.initial_image_uri
        args  = ["migrate"]

        resources {
          limits = {
            cpu    = var.container_cpu
            memory = var.container_memory
          }
        }

        env {
          name  = "DB_HOST"
          value = "/cloudsql/${google_sql_database_instance.main.connection_name}"
        }
        env {
          name  = "DB_PORT"
          value = "5432"
        }
        env {
          name  = "DB_USER"
          value = "odoo"
        }
        env {
          name  = "ODOO_DB"
          value = google_sql_database.odoo.name
        }
        env {
          name  = "FACODI_MODULES"
          value = "facodi_learning,website_facodi"
        }
        env {
          name = "DB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_password.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "ODOO_ADMIN_PASSWD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.admin_password.secret_id
              version = "latest"
            }
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }
        volume_mounts {
          name       = "filestore"
          mount_path = "/var/lib/odoo/filestore"
        }
      }

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [google_sql_database_instance.main.connection_name]
        }
      }

      volumes {
        name = "filestore"
        gcs {
          bucket        = google_storage_bucket.filestore.name
          read_only     = false
          mount_options = ["implicit-dirs", "file-mode=0666", "dir-mode=0777"]
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image]
  }

  depends_on = [
    google_project_iam_member.runtime_cloudsql,
    google_storage_bucket_iam_member.runtime_filestore,
    google_secret_manager_secret_iam_member.runtime_db_password,
    google_secret_manager_secret_iam_member.runtime_admin_password,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "deploy_invoker" {
  count    = var.runtime_enabled ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.odoo[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.deploy_service_account_email}"
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count    = var.runtime_enabled && var.public_access_enabled ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.odoo[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
