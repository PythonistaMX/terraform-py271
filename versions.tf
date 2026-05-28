terraform {
  required_version = ">= 1.6.0"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.34"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
