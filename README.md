# terraform-py271

Stack de infraestructura GCP para la aplicación `api-github-actions-demo`,
gestionado con Terraform y desplegado desde GitHub Actions con autenticación
OIDC (sin llaves estáticas de service account).

## Recursos provisionados

| Archivo | Recurso | Descripción |
|---|---|---|
| `main.tf` | `google_artifact_registry_repository` | Repositorio Docker para imágenes de la app |
| `main.tf` | `google_sql_database_instance` | Instancia Cloud SQL PostgreSQL 15 |
| `main.tf` | `google_sql_database` | Base de datos dentro de la instancia |
| `main.tf` | `google_sql_user` | Usuario de aplicación en Cloud SQL |
| `main.tf` | `google_secret_manager_secret.database_url` | Contenedor del secreto `DATABASE_URL` (valor poblado manualmente) |
| `main.tf` | `google_cloud_run_v2_service` | Servicio Cloud Run (imagen gestionada por CI/CD) |
| `iam.tf` | `google_service_account.cicd_deployer` | SA que usa GitHub Actions para desplegar |
| `iam.tf` | `google_service_account.cloud_run_runtime` | SA de ejecución del contenedor Cloud Run |
| `iam.tf` | `google_iam_workload_identity_pool` | Pool WIF para GitHub Actions |
| `iam.tf` | `google_iam_workload_identity_pool_provider` | Proveedor OIDC de GitHub |

## Outputs y su uso en GitHub Actions

Los outputs de Terraform son la fuente de verdad para las variables del entorno
`prod` en GitHub Actions. Tras un `terraform apply`:

```bash
terraform -chdir=infra/terraform-py271 output
```

| Output de Terraform | Variable en GitHub Actions |
|---|---|
| `workload_identity_provider` | `GCP_WORKLOAD_IDENTITY_PROVIDER` |
| `cicd_service_account_email` | `GCP_SERVICE_ACCOUNT` |
| `cloud_sql_instance_connection_name` | `GCP_CLOUD_SQL_CONNECTION_NAME` |
| `cloud_run_service_name` | `GCP_CLOUD_RUN_SERVICE` |
| `cloud_run_service_url` | referencia para smoke tests |
| `database_url_secret_name` | — (paso manual, ver abajo) |

### Paso manual: poblar el secreto `DATABASE_URL`

Terraform crea el contenedor del secreto pero no su valor, para que la contraseña
nunca quede en el estado de Terraform. Tras el primer `terraform apply`:

```bash
gcloud secrets versions add DATABASE_URL \
  --data-file=<(echo -n "postgresql://<db_username>:<db_password>@/<cloud_sql_database_name>?host=/cloudsql/<cloud_sql_instance_connection_name>")
```

Reemplaza los valores con los de `terraform.tfvars` y el output
`cloud_sql_instance_connection_name`. El runtime SA (`<app_name>-runtime@...`)
tiene acceso de lectura solo sobre este secreto vía
`google_secret_manager_secret_iam_member`.

## Variables de Terraform

Copia `terraform.tfvars.example` a `terraform.tfvars` y completa los valores.
La contraseña de base de datos se pasa como variable de entorno:

```bash
cp terraform.tfvars.example terraform.tfvars
export TF_VAR_db_password="<valor-seguro>"
```

| Variable | Sensible | Descripción |
|---|---|---|
| `project_id` | No | ID del proyecto GCP |
| `region` | No | Región de despliegue (ej. `us-central1`) |
| `environment` | No | Nombre del entorno: `test` o `prod` |
| `app_name` | No | Nombre lógico de la app (ej. `apiflask-demo`) |
| `artifact_repository_id` | No | ID del repositorio en Artifact Registry |
| `cloud_sql_instance_name` | No | Nombre de la instancia Cloud SQL |
| `cloud_sql_database_name` | No | Nombre de la base de datos |
| `cloud_sql_tier` | No | Tier de Cloud SQL (default: `db-f1-micro`) |
| `db_username` | No | Usuario de la app en Cloud SQL |
| `db_password` | **Sí** | Contraseña de la app — solo via `TF_VAR_db_password` |
| `enable_deletion_protection` | No | Protección contra borrado accidental (default: `true`) |
| `github_repository` | No | Repo autorizado para OIDC (formato: `org/repo`) |
| `cloud_run_service_name` | No | Nombre del servicio Cloud Run |

## Nota sobre la imagen de Cloud Run

El recurso `google_cloud_run_v2_service` se crea con una imagen placeholder
(`us-docker.pkg.dev/cloudrun/container/hello`). El pipeline de CI/CD
(`despliega-cloud-run.yaml`) actualiza la imagen en cada release.

`lifecycle.ignore_changes` en `main.tf` asegura que `terraform apply` no
revierta la imagen al placeholder en applies posteriores.

## Flujo de uso

```bash
# 1. Inicializar con backend remoto en GCS
terraform init -backend-config="bucket=<nombre-del-bucket>"

# 2. Verificar formato y sintaxis
terraform fmt -check -recursive
terraform validate

# 3. Revisar cambios antes de aplicar
terraform plan

# 4. Aplicar (solo con aprobación explícita en prod)
terraform apply
```

El workflow `.github/workflows/terraform-plan-apply.yml` automatiza este flujo
desde GitHub Actions con autenticación OIDC.
