locals {
  labels = {
    app         = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = var.artifact_repository_id
  description   = "Container images for ${var.app_name} (${var.environment})"
  format        = "DOCKER"

  labels = local.labels
}

resource "google_sql_database_instance" "app" {
  name             = var.cloud_sql_instance_name
  database_version = "POSTGRES_15"
  region           = var.region

  deletion_protection = var.enable_deletion_protection

  settings {
    tier = var.cloud_sql_tier

    backup_configuration {
      enabled = true
    }
  }
}

resource "google_sql_database" "app" {
  name     = var.cloud_sql_database_name
  instance = google_sql_database_instance.app.name
}

resource "google_sql_user" "app" {
  instance = google_sql_database_instance.app.name
  name     = var.db_username
  password = var.db_password
}
