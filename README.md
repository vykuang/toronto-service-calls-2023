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

### Env vars

#### Terraform

- project ID
- bucket name
- dataset name

How to forward them to python script prefect flow?

Once a variable is defined, terraform can accept environment variables by searching for `TF_VAR_<VAR_NAME>`. E.g. if we have `var.project_id`, we can export `TF_VARS_project_id=my-first-project` and `terraform plan` will be able to search for it.

With a key/value pair list in `.env`, export all of them in a script:

```bash
set -o allexport
source .env
set +o allexport
```

Load them in python via `dotenv`

### Setup

#### GCP

Ensure the current GCP account (not service account) has the permission to

- create projects (service accounts cannot do this without parent resource, e.g. folder/organization, and if account is free-trial, then that would not be possible)
- create service accounts
- allocate roles to princpals
- create buckets on GCS
- create datasets on BQ

The basic role of `owner` will suffice

#### Terraform

Create bucket for terraform backend and initialize

```bash
# set name
TFSTATE_BUCKET=your-bucket-name
# cd to terraform dir
cd terraform/
# make bucket
gsutil mb \
-l us-west1 \
-b on \
--pap enforced \
gs://$TFSTATE_BUCKET
# may have to add -migrate-state option if there is existing tfstate
terraform init \
-backend-config="bucket=$TFSTATE_BUCKET" \
-backend-config="prefix=terraform/state"
```


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
