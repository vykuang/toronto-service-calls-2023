terraform {
  required_version = ">= 1.0"
  # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  backend "gcs" {}
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
  }
}
provider "google" {
  project = var.project
  region = var.region
  // credentials = file(var.credentials)  # Use this if you do not want to set env-var GOOGLE_APPLICATION_CREDENTIALS
}
# resource "google_storage_bucket" "tf-state" {
#     name = var.tf_state_bucket
#     location = var.region
#     force_destroy = true
#     storage_class = var.storage_class
#     uniform_bucket_level_access = true
#     public_access_prevention = "enforced"
#     versioning {
#         enabled = true
#     }
# }
resource "google_storage_bucket" "data-lake" {
    name = var.data_lake_bucket
    location = var.region
    force_destroy = true
    storage_class = var.storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
    versioning {
        enabled = false
    }
}
# resource "google_bigquery_dataset" "dataset" {
#     dataset_id = var.bq_dataset
#     description = "Contains all tables for the 311 service call project"
#     location = var.region
# }

# defines the role to be applied
data "google_iam_policy" "prefect-role" {
    binding {
        role = "projects/de-zoom-83/roles/CustomStorageAdmin"
        members = [
            "serviceAccount:${google_service_account.prefect-agent.email}"
        ]
    }
}

# define the blank canvas service account
resource "google_service_account" "prefect-agent" {
    account_id = var.credentials_id
    display_name = var.credentials_display
    description = "Service account supplying permissions for prefect agent"
    project = var.project
}

# assign the role to the service account
resource "google_project_iam_member" "prefect-agent-iam" {
    project = var.project
    # service_account_id = google_service_account.prefect-agent.name
    role = "roles/bigquery.dataEditor"
    member = "serviceAccount:${google_service_account.prefect-agent.email}"
    #policy_data = data.google_iam_policy.prefect-role.policy_data
}

# resource "google_storage_bucket" "dp-staging" {
#     name = var.dp_staging
#     location = var.region
#     storage_class = var.storage_class
#     uniform_bucket_level_access = true
#     public_access_prevention = "enforced"
# }
# resource "google_storage_bucket" "dp-temp" {
#     name = var.dp_temp
#     location = var.region
#     storage_class = var.storage_class
#     uniform_bucket_level_access = true
#     public_access_prevention = "enforced"
# }
# resource "google_dataproc_cluster" "service-call-cluster" {
#     name = var.dp_cluster
#     region = var.region
#     graceful_decommission_timeout = "120s"
#     cluster_config {
#         staging_bucket = var.dp_staging
#         temp_bucket = var.dp_temp

#         master_config {
#             num_instances = 1
#             machine_type  = "e2-medium"
#             disk_config {
#                 boot_disk_type    = "pd-ssd"
#                 boot_disk_size_gb = 10
#             }
#         }
#         worker_config {
#             num_instances    = 2
#             machine_type     = "e2-medium"
#             min_cpu_platform = "Intel Skylake"
#             disk_config {
#                 boot_disk_size_gb = 30
#                 num_local_ssds    = 1
#             }
#         }
#         preemptible_worker_config {
#             num_instances = 0
#         }
#     }
# }
