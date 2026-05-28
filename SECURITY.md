# Security

## Modelo de identidad

### Sin llaves estáticas de service account

La autenticación de GitHub Actions a GCP usa **Workload Identity Federation (WIF)** con OIDC. No existe ningún JSON key de service account en este repositorio ni en los secretos de GitHub.

Flujo: el job obtiene un JWT firmado por GitHub → lo intercambia por un access token de corta duración en GCP Security Token Service → usa ese token para operar en GCP. El token expira al terminar el job.

### Service accounts y mínimo privilegio

| SA | Rol | Permisos |
|---|---|---|
| `cicd-deployer` | Runner de CI/CD y Terraform | Deploy en Cloud Run, push a Artifact Registry, gestión de IaC |
| `apiflask-demo-runtime` | Runtime del servicio | Solo leer los secretos que necesita + conectarse a Cloud SQL |

El SA de runtime no puede modificar infraestructura. El SA de CI/CD no puede leer datos de producción.

### Restricción del pool WIF

`attribute_condition` limita el acceso al pool a los repositorios exactos declarados en Terraform. Un fork o repositorio no autorizado no puede obtener tokens aunque conozca el identificador del pool.

El binding de suplantación añade una segunda restricción: solo jobs del entorno `prod` pueden suplantar al SA de CI/CD.

### Trade-off documentado: runner de Terraform vs. mínimo privilegio

El SA `cicd-deployer` tiene `roles/artifactregistry.admin` a nivel de proyecto porque Terraform necesita `getIamPolicy` para refrescar el estado de los recursos `iam_member` del repositorio de Artifact Registry. Este permiso no existe en roles de nivel repositorio (`writer`, `repoAdmin`).

La solución de mínimo privilegio estricto requiere separar en dos SAs: uno para Terraform (permisos amplios de gestión) y otro para el pipeline de deploy (permisos mínimos de operación). Este repositorio usa un único SA como simplificación pragmática.

## Secretos

- `DATABASE_URL`, `APP_SECRET_KEY` y `APP_SECURITY_PASSWORD_SALT` se almacenan en **Secret Manager**, no en variables de entorno ni en el estado de Terraform.
- El estado de Terraform no contiene el valor de ningún secreto: `DATABASE_URL` se referencia como `secret_key_ref` y la contraseña de base de datos se pasa como variable en tiempo de `apply`, no se escribe en el estado.
- El SA de runtime tiene `roles/secretmanager.secretAccessor` únicamente sobre los tres secretos que necesita, no a nivel de proyecto.

## Red y conectividad

- Cloud SQL no acepta conexiones TCP directas: `authorized_networks` está vacío.
- La app se conecta a Cloud SQL exclusivamente mediante socket Unix del Cloud SQL Auth Proxy en `/cloudsql/<connection_name>`.
- `ipv4_enabled = true` es un requisito del Auth Proxy para enrutar la conexión internamente, no una apertura de acceso directo. La regla de Trivy `AVD-GCP-0017` se suprime con comentario explicativo en `main.tf`.

## Estado de Terraform

- Backend remoto en Google Cloud Storage con `uniform_bucket_level_access`.
- El SA de CI/CD tiene `roles/storage.admin` únicamente sobre el bucket de estado, no a nivel de proyecto.

## Reportar una vulnerabilidad

Abre un *issue* privado o contacta al mantenedor directamente antes de publicar detalles.
