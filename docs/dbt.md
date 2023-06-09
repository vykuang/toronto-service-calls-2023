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

## dbt core

Use open source dbt-core to integrate into orchestration pipeline

### profiles.yml

- Local dbt requires a `~/.dbt/profiles.yml` which is outside of all dbt project repos
  - project specific `profiles.yml` can also be used
- It defines all the profiles that can be used within each project specific `dbt_project.yml` that *is* inside a dbt project repo
- Each profile specifies the connection info, e.g. to bigquery, or postgres
  - typically one profile for each type of data warehouse
    - top level block, below `config`
    - `org_name_db_type`, e.g. `acme_bigquery`, is a common convention for profile name
    - used in project's `dbt_project.yml`
  - `target` may be one of many in a profile, and corresponds to the different environments, e.g. `dev` for local dev that points to a dev dataset, and `prod` to point to production dataset, with different service account credentials
    - often it may be better to only have `dev` on local, and target `prod` on a separate machine, e.g. docker container
  - may contain sensitive credential materials
  - optionally populate with environment variables
    - `password: "{{ env_var('DBT_PASSWORD') }}"`
    - raise compilation error if env var not found
    - cast as int: `"{{ env_var('DBT_THREADS') | int }}"`
    - use default: `+materialized: "{{ env_var('DBT_MATERIALIZATION', 'view') }}"`
  - if profile authentication (e.g. service key) is not set properly, `dbt debug` returns `profile not found` error

### Containerization

Running a dbt as a container is fairly straightforward; bind the dbt project dir to `/usr/app/`, and bind profiles.yml to `/root/.dbt/profiles.yml`. Could also bake the code directly into the container image into artifact registry for cloud run.

Issue is authentication.

There are two main methods:

- `oauth`, which takes from your application-default and meant for end-users, and
- `service-accounts`, meant more for prod, requires setting `keyfile` to the service account key filepath
  - use `keyfile: "{{ env_var('DBT_KEYFILE') }}"` to hide sensitive information

Oauth will not work in a local container unless we bind mount the local ADC to the container, which isn't practical in prod. If we use cloud build/cloud run however, GCP is able to inject the service account credential into the container for us. [Blogpost on scheduled serverless dbt on GCP cloud run](https://atamel.dev/posts/2020/07-29_scheduled_serverless_dbt_with_bigquery/)

### docs

`dbt docs generate` creates `target/catalog.json`; `dbt docs serve` hosts a local website that displays the docs, meant for local dev

Production grade docs means hosting the info remotely on cloud storage. Site is *static*.

- [dbt docs docs](https://docs.getdbt.com/docs/collaborate/documentation#deploying-the-documentation-site)
- [hosting static website on gcs](https://cloud.google.com/storage/docs/hosting-static-website)
  - requires having my own domain
  - gcp offers domain registration
- [using app engine without needing domain](https://medium.com/hiflylabs/dbt-docs-as-a-static-website-c50a5b306514)
- [Securing the app engine site with IAP (identity-aware proxy)](https://codelabs.developers.google.com/codelabs/user-auth-with-iap#2)

#### GCS backend with load balancer

1. name bucket - `DOCS_BUCKET=$DOCS_BUCKET`
1. create gcs bucket - `gsutil mb -l us-west1 -b on $DOCS_BUCKET`
1. upload static assets - `gsutil cp file1 file2 $DOCS_BUCKET`
1. assign specialty pages - `gsutil web set -m index.html $DOCS_BUCKET`
1. set up load balancer and SSL cert - add bucket to load balancer's backend, and add google-managed SSL cert to load balancer's frontend

- load balancing > https load balancer > start config
- internet > VMs
- global https
- give name, e.g. dbt-docs-lb

1. configure frontend

- protocol > https
- IPv4
- IP addr: create and name, e.g. dbt-docs-ip, and reserve
- cert: create new cert
  - name `dbt-docs-ssl`
  - create mode: google managed
  - domain: one that we have, perhaps from gcp, e.g. www.dbt-docs.com
  - done

1. backend config

- choose name for backend bucket; name can be different from static-assets bucket
- browse, and choose the static-assets bucket created earlier
- create

1. routing rules config - automatically setup
1. Review and create
1. connect domain to load balancer

- after creation, choose our `dbt-docs-lb` balancer and note the IP
- on domain registration service, create type `A` record that points to our lb IP

1. Monitor SSL cert status; may take 60-90 min for GCP to provision the cert and make available the site
1. Try `www.dbt-docs.com`; should route to `index.html`

#### App engine

The blog combines the catalog and manifest json into index.html and deploys to GCP app engine

1. run `make_dbt_docs.py`
1. create `.gcloudignore`, allow only `targets/` and `public/`, and create `app.yaml` in dbt project root
1. deploy app.yaml in dbt project root - `gcloud app deploy`

- this uploads all files to a auto-generated gcs bucket, and deploys the app

1. browse by `gcloud app browse` or nav to the output url manually
1. secure with IAP; requires user to login with google account once set up

#### Load balancer

Load balancer distributes user traffic across multiple app instances so that no one node is overwhelmed. It acts as the frontend buffer between user traffic and the compute/storage backends. For example, it can route user to the closest geographic node for lower latency and load distribution.

It is a software-defined managed service; no physical hardware to manage.

Choose between external/internal for internet > GCP or GCP \<> GCP, and regional/global to distribute load geographically

### Orchestration

[prefect-dbt docs](https://prefecthq.github.io/prefect-dbt/#integrate-dbt-core-cli-commands-with-prefect-flows)

Requires `project_dir` and `profiles_dir` to be set, defined as either a prefect block

Basically triggers the bash `dbt` commands to run

### Implementation

- use `prefect-dbt`
  - executor needs `dbt-core` installed
    - and `dbt-bigquery` so that dbt can connect to bq
  - setup profile block
  - set profiles.yml and project folder dir
- dockerize the dbt-core and dbt-bigquery and use it to run `dbt` CLI commands
  - container has all the models baked in
  - runs code on bigquery datasets
