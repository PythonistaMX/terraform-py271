locals {
  labels = {
    app         = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }
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

    ip_configuration {
      #trivy:ignore:AVD-GCP-0017
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
      # Sin bloques authorized_networks: ninguna red puede conectarse por TCP directo.
      # Toda conexión debe pasar por Cloud SQL Auth Proxy; nunca TCP directo.
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

resource "google_secret_manager_secret" "database_url" {
  secret_id = "DATABASE_URL"

  replication {
    # auto replica la clave en todas las regiones disponibles de forma gestionada.
    # Para mayor control geográfico se puede usar user_managed con réplicas explícitas.
    auto {}
  }

  labels = local.labels
}

# Versión placeholder necesaria para que Cloud Run pueda resolver latest en el primer apply.
# ignore_changes evita que Terraform sobreescriba el valor real una vez actualizado con:
#   gcloud secrets versions add DATABASE_URL --data-file=<(echo -n "postgresql://<user>:<pass>@/<db>?host=/cloudsql/<connection_name>")
resource "google_secret_manager_secret_version" "database_url_placeholder" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "placeholder"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_cloud_run_v2_service" "app" {
  name                = var.cloud_run_service_name
  location            = var.region
  deletion_protection = var.enable_deletion_protection

  depends_on = [google_secret_manager_secret_version.database_url_placeholder]

  # Cloud Run no tiene deletion_protection nativo; la protección se gestiona
  # con IAM (revocar roles/run.admin al SA de CI/CD en prod si fuera necesario).

  template {
    # SA dedicado de runtime: principio de mínimo privilegio.
    # Solo tiene roles/cloudsql.client y roles/secretmanager.secretAccessor;
    # no puede modificar infraestructura.
    service_account = google_service_account.cloud_run_runtime.email

    containers {
      # Imagen placeholder para el primer apply.
      # lifecycle.ignore_changes evita que Terraform revierta la imagen
      # en applies posteriores; el pipeline de CI/CD gestiona las actualizaciones.
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      env {
        name  = "APP_ENV"
        value = var.environment
      }

      env {
        name = "DATABASE_URL"
        # secret_key_ref inyecta el valor en tiempo de ejecución desde Secret Manager.
        # La contraseña nunca aparece en el estado de Terraform ni en la consola de Cloud Run.
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        # Monta el socket de Cloud SQL Auth Proxy en /cloudsql/<connection_name>.
        # La app se conecta vía socket Unix; nunca expone el puerto TCP de Cloud SQL.
        instances = [google_sql_database_instance.app.connection_name]
      }
    }
  }

  lifecycle {
    # La imagen la controla el pipeline de CI/CD (gcloud run deploy).
    # Terraform gestiona configuración, SA, Cloud SQL y variables de entorno.
    ignore_changes = [template[0].containers[0].image]
  }

  labels = local.labels
}
