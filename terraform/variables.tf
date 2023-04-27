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
  type        = set(string)
  default = [
    "roles/bigquery.user",
    # "roles/secretmanager.secretAccessor",
    "roles/compute.osLogin",
    # "roles/bigquery.admin",
  ]
}
variable "prefect_blocks" {
  description = "list of prefect blocks to create"
  type        = map(any)
  default = {
    "make_infra"  = "../service_calls_311/flows/blocks/make_infra.py"
    "make_gcs_sb" = "../service_calls_311/flows/blocks/make_gcs_sb.py"
  }
}
variable "geojson_path" {
  description = "relative path to newline delimited city wards geojson"
  type        = string
  default     = "../data/city-wards-boundary-nldelim.geojson"
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

variable "gcp_network_name" {
    description = "Name of network attached to the compute instances"
    type = string
    default = "default"
}