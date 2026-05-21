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
