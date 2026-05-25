variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment name: dev, test, prod"
  type        = string
}

variable "app_name" {
  description = "Application logical name"
  type        = string
}

variable "artifact_repository_id" {
  description = "Artifact Registry repository id"
  type        = string
}

variable "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  type        = string
}

variable "cloud_sql_database_name" {
  description = "Cloud SQL database name"
  type        = string
}

variable "cloud_sql_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

variable "db_username" {
  description = "Application DB username"
  type        = string
}

variable "db_password" {
  description = "Application DB password"
  type        = string
  sensitive   = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "Repositorio de GitHub autorizado para OIDC (formato: org/repo)"
  type        = string
}

variable "cloud_run_service_name" {
  description = "Nombre del servicio Cloud Run — valor de GCP_CLOUD_RUN_SERVICE en GitHub Actions"
  type        = string
}
