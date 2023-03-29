variable "project" {
    description = "GCP project ID"
    default = "de-zoom-83"
}

variable "region" {
    description = "Region for GCP resources. Choose as per your location: https://cloud.google.com/about/locations"
    default = "us-west1"
    type = string
}

variable "storage_class" {
    description = "Storage class type for your bucket. Check official docs for more info."
    default = "STANDARD"
}

variable "data_lake_bucket" {
    description = "bucket name to store service call data"
    default = "service-calls-data-lake"
}
variable "bq_dataset" {
    description = "BigQuery Dataset that raw data (from GCS) will be written to"
    type = string
    default = "service_calls_models"
}

variable "credentials_id" {
    description = "service account ID"
    default = "prefect-agent"
}
variable "credentials_display" {
    description = "service account friendly display name"
    default = "prefect agent"
}

# variable "tf_state_bucket" {
#     description = "bucket name to store terraform state files"
#     default = "service-call-tf-states"
# }
variable "dp_staging" {
    description = "Bucket used by dataproc cluster to stage files between client and cluster"
    type = string
    default = "service-calls-dataproc-staging"
}
variable "dp_temp" {
    description = "Bucket used by dataproc cluster to store ephemeral cluster and jobs data, e.g. spark/mapreduce history"
    type = string
    default = "service-calls-dataproc-temp"
}
variable "dp_cluster" {
    description = "Name of dataproc cluster"
    type = string
    default = "service-calls-cluster"
}
