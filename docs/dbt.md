# Transformation with dbt

## dbt vs spark

### Pros

- Since all transforms can be done with SQL, dbt is the simpler choice vs spark
- no setup for clusters/staging bucket
- no overhead required to run the clusters
- the small dataset size doesn't require the distributed computing capability of spark; everything can still be done in-memory, on a single machine

### Cons

- another account/vendor to upkeep? vs only GCP

## Setup

- Connect Bigquery to dbt
  - create service account for dbt with the necessary bigquery permissions
    - viewer - all GCP
    - bq data editor
    - bq job user
    - bq user
    - **bigquery.datasets.create**
  - permission analysis shows all the excessive permissions so there is opportunity to make it more secure
  - Manage key -> add key -> download json key file
- Configure project setup on dbt cloud
  - upload the json key
  - set the dev `dataset`
    - this does not need to be created beforehand
- setup repo via github to allow continuous integration (e.g. run jobs on pull requests)
  - git clone/@git will not enable CI
  - alternatively, create managed repository via dbt, if the email used for dbt cloud is different from the email linked to your github account
    - meant to trial dbt without needing a new repo
    - must contact support to transfer contents out
    - does not support pull requests, and so cannot automatically invoke `dbt build`
- prepare the raw datasets in the data warehouse for dbt to source from
  - loading the data into the warehouse will be part of the upstream pipeline as orchestrated by prefect

## API access

Orchestrating cloud dbt via API requires paid accounts.

1. Clone the dbt models repository
1. Create cloud dbt account
1. Connect to the bigquery dataset created from terraform
1. Connect to the dbt models repository
1. Create job with command `dbt build --var="is_test_run:false"`
1. Note API key, account ID and job ID; Prefect requires these info to orchestrate dbt cloud jobs
   - account ID: account settings -> the digits after `accounts/` in the url
   - API key: left nav -> API access -> copy API key
   - job ID: deploy -> jobs -> digits after `jobs/` in URL; only available after job has been created in UI
1. Create prefect block `dbt cloud credentials` with API key and account ID; use `dbt-service-cred` for block name

## Poverty dbt

Schedule the job on the UI instead of via prefect

Think about migrating to dbt-core...

### profiles.yml

- Local dbt requires a `~/.dbt/profiles.yml` which is outside of all dbt project repos
- It defines all the profiles that can be used within each project specific `dbt_project.yml` that *is* inside a dbt project repo
- Each profile specifies the connection info, e.g. to bigquery, or postgres
  - typically one profile for each type of data warehouse
  - may contain sensitive credential materials
  - optionally populate with environment variables
    - `password: "{{ env_var('DBT_PASSWORD') }}"`
    - raise compilation error if env var not found
    - cast as int: `"{{ env_var('DBT_THREADS') | int }}"`
    - use default: `+materialized: "{{ env_var('DBT_MATERIALIZATION', 'view') }}"`
  - if profile authentication (e.g. service key) is not set properly, `dbt debug` returns `profile not found` error
