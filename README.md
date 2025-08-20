# Data engineering zoomcamp - 311 Service Calls

This is a visualization of the service calls initiated by Toronto citizens. The choropleth map is broken down into the resident's ward, as well as the types of requests being made. The result is a heatmap of the types of service requests fulfilled for each neighborhood in Toronto.

- [Data engineering zoomcamp - 311 Service Calls](#data-engineering-zoomcamp---311-service-calls)
  - [Motivation](#motivation)
  - [Data visualization](#data-visualization)
  - [Project architecture](#project-architecture)
  - [Run it yourself](#run-it-yourself)
    - [0 Setup](#0-setup)
    - [1 GCP](#1-gcp)
    - [2 Set Environment variables](#2-set-environment-variables)
    - [3 Terraform](#3-terraform)
    - [4 dbt](#4-dbt)
    - [5 Prefect](#5-prefect)
    - [\[optional\] docker](#--optional---docker)
  - [data resources](#data-resources)
  - [Peer Review Criteria](#peer-review-criteria)

<small><i><a href='http://ecotrust-canada.github.io/markdown-toc/'>Table of contents generated with markdown-toc</a></i></small>

## Motivation

Besides finding the area with the most noise complaints, this project is an exercise in implementing a data pipeline that incorporates reliability, traceability, and resiliency. Concretely speaking, a pipeline following those principles should have these characteristics:

- restartable - can each step be replayed without introducing duplicates or creating errors?
- monitoring and logging - each step should provide some heartbeat pulse if successful, or error logs if otherwise
- simple - no extra code
- able to handle schema drift *or* enforce a data contract
- efficiency - relating to reliability, how do we model our data to minimize compute? E.g. partitioning and/or clustering, or creating a compact view for end-user to query against, instead of querying against the whole dataset
- able to handle late data
- good data quality - processing to remove void entries, e.g. entries missing ward or FSA code
- scalability - if there's no work, it should scale to 0 nodes; conversely it should be elastic to handle increased workload by scaling horizontally

## Data visualization

[Link to Looker dashboard](https://lookerstudio.google.com/reporting/fb6bd9a4-9efc-4999-bd81-d850dd25e51d)

![looker visualization](img/looker-screen.png)

## Project architecture

![service pipeline diagram](img/pipeline-diagram.png)

- Data is pulled on a monthly basis to sync with its refresh rate at the source
- data lake: GCS
  - stores raw csv and schema'd parquets
  - remove outliers in dates
  - remove entries without ward/FSA data
  - feature engineer
    - add `seasons`
- data warehouse: Bigquery
  - part of extraction to create a facts table with the schema'd parquets from gcs
  - stores the various models used for visualizations
  - partitioning/clustering
- transform: dbt
  - models the raw datasets that have been loaded onto bigquery
  - documentation
  - tests for schema drift
- orchestration: Prefect
  - facilitates monthly refresh: pull, process, store models
  - monitoring and logging
  - restarts
  - handles late data
  - executes via dockerized apps
- execution: Cloud Run
  - stateless, containerized app
  - images stored on Artifact Registry
  - dockerfiles sent to Cloud Build
- Visualization: Looker
  - combine with geojson to produce choropleth map
- Security: Cloud IAM
  - [service account with necessary permissions to manage cloud resources](https://registry.terraform.io/modules/terraform-google-modules/service-accounts/google/latest)
- IaC: Terraform
  - responsible for cloud infra
  - gcs bucket
  - bigquery dataset
  - artifact registry
  - cloud run jobs

## Run it yourself

Clone this repo to start: `git clone https://github.com/vykuang/toronto-service-calls-2023.git`

### 0 Setup

Local requirements:

- python 3.11
- poetry to manage python package dependencies
    - `poetry install` inside project root
- gcloud - local credential should have enough permissions to create all necessary cloud resources on GCP, e.g. owner
- gsutil
- terraform

### 1 GCP

Create project via console

Note the `PROJECT_ID`; will need to assign in `user.env`

To use any resource, the new project must be linked to a billing account. In console nav menu, go to Billing > Link to billing account. Default should be called `My Billing Account` if on free trial

After creating project, create application default credential for terraform:

```bash
PROJECT_ID=[YOUR_PROJECT_ID]
gcloud auth application-default login --project=$PROJECT_ID
gcloud config set project $PROJECT_ID
```

### 2 Set Environment variables in user.env

Once a variable is defined, terraform can accept environment variables by searching for `TF_VAR_<VAR_NAME>`. E.g. if we have `var.project_id`, we can export `TF_VARS_project_id=my-first-project` and `terraform plan` will populate the variable correctly.

Default `user.env` to be filled in:

```bash
# default user.env file

TF_VAR_project_id= # fill here after creating project #
TF_VAR_region=us-west1  # change any of these to your liking
TF_VAR_zone=us-west1-b
TF_VAR_data_lake_bucket=service-data-lake
TF_VAR_bq_dataset=service_calls_models
TFSTATE_BUCKET=tf-state-service
```

After filling in `TF_VAR_project_id`, run this blurb in project root to export `user.env` to environment

```bash
set -o allexport
. user.env
set +o allexport
```

### 3 Terraform

- Create bucket for terraform backend and initialize
- Creates resources for the project

```bash
# cd to terraform dir
cd terraform/
# make bucket for remote backend
gsutil mb \
-l $TF_VAR_region \
-p $TF_VAR_project_id \
-b on \
--pap enforced \
gs://$TFSTATE_BUCKET
# turn on versioning
gsutil versioning set on gs://$TFSTATE_BUCKET
# may have to add -migrate-state option if there is existing tfstate
terraform init \
-backend-config="bucket=$TFSTATE_BUCKET" \
-backend-config="prefix=terraform/state"
# -migrate-state
terraform apply
```

`terraform apply` will create:

- GCS bucket
- bigquery dataset
- GCE e2-medium instance with container optimized images (COS):
  - `server` orchestrates prefect flow
    - start-up script pulls prefect, and runs dockerized prefect server
  - `worker` executes prefect flow which triggers cloud run jobs
  - instance type: `e2-medium`; anything less have not been able to run prefect server/worker in my experience
    - *this is beyond free tier eligibility and will incur costs*
- cloud build job that submits the dockerfiles
- artifact registry to store the docker image for extract-load and dbt
- cloud run jobs which pulls those images to execute our pipeline
- service account with permissions to access the above resources

View prefect server UI after creation completes at `http://{server-external-IP}:4200`

### 4 Prefect

Deploy the flow; scheduled to run on 1st of every month

```sh
PREFECT_SERVER_HOST=$(gcloud compute instances list --filter="name=('server')" --format "value(EXTERNAL_IP)")
export PREFECT_API_URL=http://$PREFECT_SERVER_HOST:4200/api
cd service_calls_311 && ./deploy.py --apply --run
```

## data resources

Full credits to statscan and open data toronto for providing these datasets.

- [311 service requests](https://open.toronto.ca/dataset/311-service-requests-customer-initiated/)
- [city ward geojson](https://open.toronto.ca/dataset/city-wards/)
- [forward sortation area boundary file](https://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/bound-limit-2016-eng.cfm)
  - FSA is the first three characters in the postal code and correspond roughly to a neighborhood
- [Article on converting that to geojson](https://medium.com/dataexplorations/generating-geojson-file-for-toronto-fsas-9b478a059f04)

## Peer Review Criteria

- Cloud - GCP and terraform
- data ingestion - extract and load subflows; intermediate storage in GCS
- data warehouse - bigquery, partition by datetime, cluster by ward and service type
- transformations - dbt
- dashboard - looker with choropleth and ward ranking by request type

## Notes for improvements

- host dbt-core's documentations on GCS as [static website](https://cloud.google.com/storage/docs/hosting-static-website)
- tests for the `extract_load` flow
- migrate the executor to cloud run so that resources are used only when a flow deployment is active, instead of continuously running a GCE instance
- integrate GCP's artifacts registry and cloud build to create a private docker repository that only the service account may retrieve
- promote the GCE ephemeral IP to permanent

### To-do

- create new GCP trial instance?
- revise flow to include dbt-core
  - add subflow to trigger dbt commands
  - need to use `prefect_dbt.cli` module to load `DbtCliProfile` and invoke `DbtCoreOperation`?
  - can the dbt-core models repo be integrated to this repo?
  - host docs on app engine?
  - run a local flow with just the dbt portion
  - or fold dbt into container for cloud run
- convert the executor agent to cloud run
  - invoked only when flow is scheduled
  - server should remain as a persistent VM instance
- update transformations
  - group similar service request types, e.g. roadkills/cadavers, waste pickups, etc.
- integrate artifacts registry/cloud build as part of the pipeline to create private docker repo
