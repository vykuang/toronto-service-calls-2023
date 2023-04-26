# Data engineering zoomcamp - 311 Service Calls

This is a visualization of the service calls initiated by Toronto citizens. The choropleth map is broken down into the resident's ward and their forward sortation area (FSA), as well as the types of requests being made. The result is a heatmap of the types of service requests fulfilled for each neighborhood in Toronto.

## Motivation

Besides finding the area with the most noise complaints, this project is an exercise in implementing a data pipeline that incorporates reliability, traceability, and resiliency. Concretely speaking, a pipeline following those principles should have these characteristics:

- restartable - can each step be replayed without introducing duplicates or creating errors?
- monitoring and logging - each step should provide some heartbeat pulse if successful, or error logs if otherwise
- simple - no extra code
- able to handle schema drift *or* enforce a data contract
- efficiency - relating to reliability, how do we model our data to minimize compute? Perhaps via partitioning and/or clustering, or creating a compact view for end-user to query against, instead of querying against the whole dataset
- able to handle late data
- good data quality - processing to remove void entries, e.g. entries missing ward or FSA code

## Data visualization

## Project architecture

- Data is pulled on a monthly basis to sync with its refresh rate at the source
- data lake: GCS
  - stores raw csv and schema'd parquets
- ~~batch processing: dataproc (spark)~~
  - replaced in favour of dbt since distributed computing is not required here
  - remove outliers in dates
  - remove entries without ward/FSA data
  - feature engineer
- data warehouse: Bigquery
  - part of extraction to create a facts table with the schema'd parquets from gcs
    - [`create_table` docs](https://cloud.google.com/python/docs/reference/bigquery/latest/google.cloud.bigquery.client.Client#google_cloud_bigquery_client_Client_create_table)
  - stores the various models used for visualizations
  - partitioning/clustering
- transform: dbt
  - models the raw datasets that have been loaded onto bigquery
  - documentation
  - tests
- orchestration: Prefect
  - facilitates monthly refresh: pull, process, store models
  - monitoring and logging
  - restarts
  - handles late data
- Visualization: Metabase/Streamlit
  - combine with geojson to produce choropleth map
- IaC: Terraform
  - responsible for cloud infra
  - gcs bucket
  - bigquery dataset
  - [service account with necessary permissions to manage cloud resources](https://registry.terraform.io/modules/terraform-google-modules/service-accounts/google/latest)
  - ~~dataproc cluster~~

## Run it yourself!

Clone this repo to start

### Env vars

#### Terraform

- project ID
- bucket name
- dataset name

Once a variable is defined, terraform can accept environment variables by searching for `TF_VAR_<VAR_NAME>`. E.g. if we have `var.project_id`, we can export `TF_VARS_project_id=my-first-project` and `terraform plan` will be able to search for it.

With a key/value pair list in `.env`, export all of them in a script:

```bash
# .env file
TF_VAR_project_id=
TF_VAR_region=
TF_VAR_zone=
TFSTATE_BUCKET=tf-state-service
```

```bash
set -o allexport
source ../.env
set +o allexport
```

### Setup

#### GCP

Create project:

- via console, or
- via `gcloud projects create <PROJECT_ID>`

The `PROJECT_ID` can be anything, but the default as specified in `variables.tf` is `service-calls-pipeline`; if you choose different, make sure they match.

To use any resource, the new project must be linked to a billing account. In console nav menu, go to Billing > Link to billing account. Default should be called `My Billing Account` if on free trial

#### Terraform

- Create bucket for terraform backend and initialize
- Ensure the current user account has admin level status on the created project
  - gcs read/write
  - bigquery load
  - secret accessor

```bash
# cd to terraform dir
cd terraform/
# make bucket
gsutil mb \
-l $TF_VAR_region \
-p $TF_VAR_project_id \
-b on \
--pap enforced \
gs://$TFSTATE_BUCKET
# turn on versioning
gsutil versioning set on gs://$TF_VAR_data_lake_bucket
# may have to add -migrate-state option if there is existing tfstate
terraform init \
-backend-config="bucket=$TFSTATE_BUCKET" \
-backend-config="prefix=terraform/state" \
-migrate-state
terraform apply
```

`terraform apply` will create:

- GCS bucket
- bq dataset
- GCE instance, `server`, to orchestrate prefect flow
- GCE instance, `agent`, to execute prefect flow
- service account with permissions to access the above resources

#### Prefect

`make_infra.py` must be run on the prefect agent instance so that the credential volume is mounted properly

- integrate into terraform as part of instance initiation
- `metadata_startup_script` will execute `make_infra.py`

#### dbt

1. Clone the dbt models repository
1. Create cloud dbt account
1. Connect to the bigquery dataset created from terraform
1. Connect to the dbt models repository
1. Create job with command `dbt build --var="is_test_run:false"`
1. Schedule the job on a monthly basis, to align with the frequency of the dataset update


## data resources

Full credits to statscan and open data toronto for providing these datasets.

- [city ward geojson](https://open.toronto.ca/dataset/city-wards/)
- [forward sortation area boundary file](https://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/bound-limit-2016-eng.cfm)
  - FSA is the first three characters in the postal code and correspond roughly to a neighborhood
- [Article on converting that to geojson](https://medium.com/dataexplorations/generating-geojson-file-for-toronto-fsas-9b478a059f04)
- [311 service requests](https://open.toronto.ca/dataset/311-service-requests-customer-initiated/)
- [article on using folium](https://realpython.com/python-folium-web-maps-from-data/)

## Log

- 23/3/14 - Outline project architecture - 311 service calls
- 23/3/15 - download 311 service data from open data toronto
- 23/3/16 - choropleth with geojson in folium
- 23/3/22 - add transform - UDF to extract season
- 23/3/24 - add transform - SQL `CASE WHEN` to extract season
- 23/3/25 - add transform - top *n* types per ward, per season, and wards per type
- 23/4/xx - terraform and prefect
- 23/4/10 - dockerize the prefect service agent
- 23/4/22 - convert spark to bigquery sql
- 23/4/23 - looker choropleth
- 23/4/23 - code reproduction
- 26/4/23 - load geojson with terraform; pivot from dbt orchestration to manual schedule; deploy and run prefect flow
