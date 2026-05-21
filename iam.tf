# Service account que el pipeline usa para desplegar en GCP.
resource "google_service_account" "cicd_deployer" {
  account_id   = "cicd-deployer"
  display_name = "CI/CD deployer — ${var.environment}"
  description  = "Gestionado por Terraform. Autenticado desde GitHub Actions via OIDC."
}

locals {
  cicd_roles = [
    "roles/artifactregistry.writer",
    "roles/run.admin",
    "roles/iam.serviceAccountUser",
  ]
}

resource "google_project_iam_member" "cicd_roles" {
  for_each = toset(local.cicd_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.cicd_deployer.email}"
}

# Pool de identidades: perímetro de confianza para sistemas CI externos.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
}

# Proveedor OIDC de GitHub dentro del pool.
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
  }

  # Solo este repositorio puede solicitar tokens contra este pool.
  attribute_condition = "attribute.repository == '${var.github_repository}'"
}

# Solo jobs del entorno correcto pueden suplantar al service account.
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.cicd_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${var.environment}"
}
