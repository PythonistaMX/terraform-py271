# Service account que el pipeline usa para desplegar en GCP.
resource "google_service_account" "cicd_deployer" {
  account_id   = "cicd-deployer"
  display_name = "CI/CD deployer — ${var.environment}"
  description  = "Gestionado por Terraform. Autenticado desde GitHub Actions via OIDC."
}

locals {
  cicd_roles = [
    # Deploy de Cloud Run
    "roles/run.admin",
    # Suplantar el SA de runtime al desplegar
    "roles/iam.serviceAccountUser",
    # Leer secretos en gcloud run deploy --update-secrets
    "roles/secretmanager.viewer",
    # Crear/modificar secretos en Secret Manager (terraform apply)
    "roles/secretmanager.admin",
    # Gestionar instancias, bases de datos y usuarios de Cloud SQL
    "roles/cloudsql.admin",
    # Crear SAs y gestionar sus IAM bindings (google_service_account_iam_member)
    "roles/iam.serviceAccountAdmin",
    # Crear y configurar el WIF pool y provider
    "roles/iam.workloadIdentityPoolAdmin",
    # Gestionar bindings IAM a nivel de proyecto (google_project_iam_member)
    "roles/resourcemanager.projectIamAdmin",
  ]
}

# trivy:ignore:AVD-GCP-0006
# trivy:ignore:AVD-GCP-0049
resource "google_project_iam_member" "cicd_roles" {
  for_each = toset(local.cicd_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.cicd_deployer.email}"
}

# Permiso de lectura/escritura al bucket del estado de Terraform.
# Otorgado al nivel de bucket (no de proyecto) para mínimo privilegio.
resource "google_storage_bucket_iam_member" "cicd_state" {
  bucket = var.tf_state_bucket
  # storage.admin a nivel de bucket (no de proyecto): incluye getIamPolicy,
  # necesario para que Terraform refresque este recurso en cada plan.
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.cicd_deployer.email}"
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

  # Restringe el pool a estos dos repositorios exactos. Sin esta condición,
  # cualquier repositorio de GitHub podría solicitar un token de corta duración
  # contra este pool y potencialmente suplantar al SA de CI/CD.
  attribute_condition = "attribute.repository in ['${var.github_repository}', '${var.github_infra_repository}']"
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

# Permite al SA de CI/CD generar identity tokens impersonándose a sí mismo.
# Necesario para el smoke test: gcloud auth print-identity-token no funciona
# con credenciales WIF sin impersonación explícita.
resource "google_service_account_iam_member" "cicd_self_token_creator" {
  service_account_id = google_service_account.cicd_deployer.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.cicd_deployer.email}"
}

# Permite al SA de CI/CD invocar el servicio Cloud Run para el smoke test.
resource "google_cloud_run_v2_service_iam_member" "cicd_invoker" {
  name     = google_cloud_run_v2_service.app.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.cicd_deployer.email}"
}

# Acceso público intencional: la API es de consulta abierta (demo).
# Para un servicio privado: eliminar este recurso y autenticar con identity tokens.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  name     = google_cloud_run_v2_service.app.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# El SA de runtime necesita leer DATABASE_URL de Secret Manager en tiempo de ejecución.
# El permiso se otorga solo sobre este secreto (no a nivel de proyecto) para mínimo privilegio.
resource "google_secret_manager_secret_iam_member" "runtime_database_url" {
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}

# El SA de CI/CD necesita push de imágenes y leer/modificar la política IAM del repositorio.
# repoAdmin en lugar de writer: Terraform requiere getIamPolicy al refrescar el estado
# de google_artifact_registry_repository_iam_member; writer no incluye ese permiso.
resource "google_artifact_registry_repository_iam_member" "cicd_push" {
  repository = google_artifact_registry_repository.app.name
  location   = var.region
  role       = "roles/artifactregistry.repoAdmin"
  member     = "serviceAccount:${google_service_account.cicd_deployer.email}"
}

# El SA de runtime necesita hacer pull de imágenes desde Artifact Registry.
resource "google_artifact_registry_repository_iam_member" "runtime_pull" {
  repository = google_artifact_registry_repository.app.name
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.cloud_run_runtime.email}"
}
