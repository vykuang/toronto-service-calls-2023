# Terraform

At its simplest, simply specify a `main.tf` with a `resource` block:

```tf
# main.tf
resource "google_storage_bucket" "data-lake" {
    name = data_lake_bucket_name
    location = gcp_region
    force_destroy = true
    storage_class = some_storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
}
```

then run these commands

```bash
terraform init
terraform apply
```

to have terraform build the specified bucket.

## Backend

[Offical docs](https://developer.hashicorp.com/terraform/language/settings/backends/configuration#partial-configuration)

This is the storage for the `.tfstate` state files, where terraform keeps record of the state of cloud infrastructure. Specify in top level `terraform` block inside `main.tf`:

```tf
# main.tf
terraform {
  required_version = ">= 1.0"
  # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  backend "gcs" {
    bucket = "service-call-tf-states"
    prefix = "terraform/state"
  }  
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
  }
}
```

Most likely we'll want some remote cloud storage. Paradox is that the backend bucket needs to be made beforehand for terraform to use it. So we need to manually make a bucket before letting terraform build our cloud infra? It's not unreasonable, but appears a little counter-intuitive. 
`terraform` block also does not allow input variables (from `variables.tf`) to be used, but allows the `backend` block to be configured via these methods when running `terraform init`, *if the backend block exists, and is empty*:

1. CLI argument: `-backend-config="KEY=VALUE"`; repeat for each K/V pair
1. file: `-backend-config=path/to/config.gcs.tfbackend`
    - file lists all the `KEY = VALUE` pairs in top level

To parametrize the backend bucket, CLI seems more approachable. 

```bash
# set name for tfstate bucket
TFSTATE_BUCKET=some_gcs_bucket`
# make bucket; 
# -l: region; -b on: uniform access; --pap: public access prevention
gsutil mb \
    -l us-west1 \
    -b on \
    --pap enforced \
    gs://$TFSTATE_BUCKET
# may have to add -migrate-state option
terraform init \
    -backend-config="bucket=$TFSTATE_BUCKET" \
    -backend-config="prefix=terraform/state"
```

If successful, in addition to terminal log, a `.terraform/` folder and `.terraform.lock.hcl` file will appear
## Provider

Specify our project ID, default region, and if not already on GCE, path to cloud credential

```tf
provider "google" {
    project = var.project
    region = var.region
    # Use this if you do not want to set env var GOOGLE_APPLICATION_CREDENTIALS
    # credentials in variables.tf has path to file
    // credentials = file(var.credentials)  
}
```

## Resources

[gcp provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

- gcs bucket as data lake and storage for dataproc cluster
- bigquery dataset
- dataproc cluster

```tf
resource "google_storage_bucket" "data-lake" {
    name = var.data_lake_bucket
    location = var.region
    force_destroy = true
    storage_class = var.storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
}
resource "google_bigquery_dataset" "dataset" {
    dataset_id = var.bq_dataset
    description = "Contains all models for the 311 service call project"
    location = var.region
}
resource "google_storage_bucket" "dp-staging" {
    name = var.dp_staging
    location = var.region
    storage_class = var.storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
}
resource "google_storage_bucket" "dp-temp" {
    name = var.dp_temp
    location = var.region
    storage_class = var.storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
}
resource "google_dataproc_cluster" "service-call-cluster" {
    name = var.dp_cluster
    region = var.region
    description = "Runs spark jobs for the service call project"
    cluster_config {
        staging_bucket = var.dp_staging
        temp_bucket = var.dp_temp
    }
}
```