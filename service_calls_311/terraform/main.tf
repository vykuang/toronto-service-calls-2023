terraform {
  required_version = ">= 1.0"
  # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  backend "gcs" {}
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}
provider "google" {
  project = var.project
  region  = var.region
  // credentials = file(var.credentials)  # Use this if you do not want to set env-var GOOGLE_APPLICATION_CREDENTIALS
}

resource "google_storage_bucket" "data-lake" {
  name                        = var.data_lake_bucket
  location                    = var.region
  force_destroy               = true
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning {
    enabled = false
  }
}
# resource "google_bigquery_dataset" "dataset" {
#     dataset_id = var.bq_dataset
#     description = "Contains all tables for the 311 service call project"
#     location = var.region
# }


# define the blank canvas service account
resource "google_service_account" "prefect-agent" {
  account_id   = var.service_account_id
  display_name = var.service_account_name
  description  = "Service account supplying permissions for prefect agent"
  project      = var.project
}

resource "google_project_iam_custom_role" "custom-prefect-role" {
  role_id = "customPrefectAgent"
  title   = "Custom Prefect Agent"
  # agent_permissions defined in variables.tf as set of strings
  permissions = [for allow in var.agent_permissions : allow]
  description = "Custom role for agent to access cloud storage and create bigquery tables"
}

# assign the role to the service account
resource "google_project_iam_member" "prefect-agent-iam" {
  project = var.project
  # assigning predefined roles
  # for_each = var.prefect_roles
  # role = each.key
  # assigning the custom role
  role   = google_project_iam_custom_role.custom-prefect-role.id
  member = "serviceAccount:${google_service_account.prefect-agent.email}"
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
