output "artifact_repository_url" {
  description = "Artifact Registry repository URL prefix"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "cloud_sql_instance_connection_name" {
  description = "Cloud SQL instance connection name"
  value       = google_sql_database_instance.app.connection_name
}

output "cloud_sql_database_name" {
  description = "Cloud SQL database name"
  value       = google_sql_database.app.name
}

output "workload_identity_provider" {
  description = "Nombre del WIF provider — valor de GCP_WORKLOAD_IDENTITY_PROVIDER en GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "cicd_service_account_email" {
  description = "Email del SA de CI/CD — valor de GCP_SERVICE_ACCOUNT en GitHub Actions"
  value       = google_service_account.cicd_deployer.email
}

output "cloud_run_service_name" {
  description = "Nombre del servicio Cloud Run — valor de GCP_CLOUD_RUN_SERVICE en GitHub Actions"
  value       = google_cloud_run_v2_service.app.name
}

output "cloud_run_service_url" {
  description = "URL pública del servicio Cloud Run"
  value       = google_cloud_run_v2_service.app.uri
}

output "database_url_secret_name" {
  description = "Nombre del secreto de DATABASE_URL en Secret Manager — poblar con: gcloud secrets versions add DATABASE_URL --data-file=<(echo -n 'postgresql://...')"
  value       = google_secret_manager_secret.database_url.secret_id
}
