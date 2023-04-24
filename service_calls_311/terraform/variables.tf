variable "project_id" {
  type        = string
  default     = null
  description = "GCP project ID"
}
variable "project_name" {
  type        = string
  default     = "Service Calls Toronto Pipeline"
  description = "GCP project display name"
}
variable "region" {
  type        = string
  default     = null
  description = "Region for GCP resources. Choose as per your location: https://cloud.google.com/about/locations"
}
variable "zone" {
  type    = string
  default = null
}

variable "data_lake_bucket" {
  type        = string
  default     = null
  description = "bucket name to store service call data"
}
variable "bq_dataset" {
  type        = string
  default     = null
  description = "BigQuery Dataset that raw data (from GCS) will be written to"
}

variable "service_account_id" {
  type        = string
  default     = "service-agent"
  description = "service account ID"
}
variable "service_account_name" {
  type        = string
  default     = "service agent"
  description = "service account friendly display name"
}
# not req'd if we're defining the specific permissions
variable "prefect_roles" {
    description = "list of roles assigned to the executor service account"
    type = set(string)
    default = [
        "roles/bigquery.user",
        "roles/secretmanager.secretAccessor",
        "roles/compute.osLogin",
    ]
}
variable "agent_permissions" {
  type = set(string)
  default = [
    "bigquery.tables.create",
    "bigquery.tables.updateData",
    "bigquery.tables.update",
    "bigquery.jobs.create",
    "bigquery.datasets.create",
    "storage.buckets.get",
    "storage.objects.get",
    "storage.objects.list",
  ]
  description = "list of permissions for the custom agent role"
}

variable "gcp_service_list" {
  type = set(string)
  default = [
    "compute.googleapis.com",
    "storage-component.googleapis.com",
    "bigquery.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com"
  ]
  description = "APIs to be enabled in GCP project"
}

variable "prefect_api_key" {
    type = string
    description = "API key to authenticate with remote prefect cloud workspace"
}

# variable "tf_state_bucket" {
#     description = "bucket name to store terraform state files"
#     default = "service-call-tf-states"
# }
# variable "dp_staging" {
#   description = "Bucket used by dataproc cluster to stage files between client and cluster"
#   type        = string
#   default     = "service-calls-dataproc-staging"
# }
# variable "dp_temp" {
#   description = "Bucket used by dataproc cluster to store ephemeral cluster and jobs data, e.g. spark/mapreduce history"
#   type        = string
#   default     = "service-calls-dataproc-temp"
# }
# variable "dp_cluster" {
#   description = "Name of dataproc cluster"
#   type        = string
#   default     = "service-calls-cluster"
# }
