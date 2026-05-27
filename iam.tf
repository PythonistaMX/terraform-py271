# Service account que el pipeline usa para desplegar en GCP.
resource "google_service_account" "cicd_deployer" {
  account_id   = "cicd-deployer"
  display_name = "CI/CD deployer — ${var.environment}"
  description  = "Gestionado por Terraform. Autenticado desde GitHub Actions via OIDC."
}

locals {
  cicd_roles = [
    "roles/run.admin",
    "roles/iam.serviceAccountUser",
    # Necesario para referenciar secretos en `gcloud run deploy --update-secrets`.
    # Sin este rol el deploy falla al intentar montar APP_SECRET_KEY y APP_SECURITY_PASSWORD_SALT.
    "roles/secretmanager.viewer",
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

# SA de runtime de Cloud Run: identidad con la que corre el contenedor en producción.
# Separado del SA de CI/CD para aplicar mínimo privilegio: el runtime no puede
# desplegar ni modificar infraestructura; solo leer de Cloud SQL.
resource "google_service_account" "cloud_run_runtime" {
  account_id   = "${var.app_name}-runtime"
  display_name = "Cloud Run runtime — ${var.environment}"
  description  = "Identidad de ejecución del servicio Cloud Run. Gestionado por Terraform."
}

# Permite al SA de runtime conectarse a Cloud SQL vía Auth Proxy (socket Unix).
resource "google_project_iam_member" "cloud_run_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}

# El SA de CI/CD necesita actuar como el SA de runtime para poder desplegarlo.
# Sin este binding, gcloud run deploy falla con "Permission denied on service account".
resource "google_service_account_iam_member" "cicd_act_as_runtime" {
  service_account_id = google_service_account.cloud_run_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cicd_deployer.email}"
}

# El SA de runtime necesita leer DATABASE_URL de Secret Manager en tiempo de ejecución.
# El permiso se otorga solo sobre este secreto (no a nivel de proyecto) para mínimo privilegio.
resource "google_secret_manager_secret_iam_member" "runtime_database_url" {
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}
