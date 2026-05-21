# terraform-py271

Base de infraestructura parametrizada para GCP usando Terraform.

## Objetivo

Este stack esta preparado para consumir configuracion desde GitHub Actions Environments
mediante `vars` (no sensibles) y `secrets` (sensibles), con autenticacion OIDC.

## Recursos incluidos

- Artifact Registry para imagenes de la app.
- Cloud SQL PostgreSQL (instancia, base y usuario).

## Variables Terraform esperadas

No sensibles (GitHub Environment Variables):

- `GCP_PROJECT_ID`
- `GCP_REGION`
- `APP_NAME`
- `ARTIFACT_REPOSITORY_ID`
- `CLOUD_SQL_INSTANCE_NAME`
- `CLOUD_SQL_DATABASE_NAME`
- `CLOUD_SQL_TIER`
- `DB_USERNAME`
- `ENABLE_DELETION_PROTECTION`
- `TF_STATE_BUCKET`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`

Sensibles (GitHub Environment Secrets):

- `DB_PASSWORD`

## Flujo recomendado en GitHub Actions

1. Seleccionar entorno (`test` o `prod`).
2. Autenticar con OIDC (`id-token: write`) contra GCP.
3. Ejecutar `terraform init`, `validate` y `plan`.
4. Ejecutar `apply` solo con aprobacion explicita.

Workflow de referencia: `.github/workflows/terraform-plan-apply.yml`

## Uso local rapido

```bash
terraform init
terraform validate
terraform plan
```