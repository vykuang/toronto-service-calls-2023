# Potholes

Summary of problems along the way

## Fetch

- Field in `Ward` not following the `ward name (ward_id)` format
  - add `try/except` block
- certain rows having more than expected field
  - add `on_bad_lines='skip'` in `pd.read_csv`
- FileNotFound: Zip in lower case, but csv in upper case
  - more robust method to look for csv - glob `*.csv` instead
- `IndexError: string index out of range` when instantiating bucket: env var not passed, or not set correctly
  - add validation check for bucket and dataset name
  - must `export TF_VAR_...=` prior to running script
- `load_dotenv` will not substitute environment variables when importing `.env` file, i.e. cannot set `VAR2=${VAR1}`; `VAR2` will be set literally

## Terraform

- Remote backend must already exist for terraform to initialize; bucket must be separate from `main.tf`, as it cannot use a bucket it built as its own backend
- project creation cannot be done on a service account without a parent resource, i.e. folder or organization
  - could be related to free-trial status, but I was unable to add `projectCreator` role to any service account even on console
  - changing SA to the basic role of `owner` also did not grant `projects.create` permission
    - `roles/resourcemanager.projectCreator` must be assigned via `gcloud organizations ...`
    ```
    gcloud organizations add-iam-policy-binding 0 \
        --member=serviceAccount:<SA_EMAIL> \
        --role=roles/resourcemanager.projectCreator
    ```
    - Since there is no org, this command also does not work
  - cloud shell on the owner user account was able to run `gcloud projects create test-proj-83` without specifying parent resource
  - I think personal machines should authenticate with user accounts
    - `gcloud auth login --no-browser` requires copy-pasting the cmd to *a second machine that does have a browser with gcloud installed*
    - not sure how that'll shake out on windows WSL2; install on powershell???
    - [looks like it](https://cloud.google.com/sdk/docs/install#windows)
    - WSL2 on my desktop was able to open browser for the normal auth workflow
  - other resources that depend on the project creation failed if the project creation isn't registered in time
    - "error 400: unknown project id"
    - "Error 403: Permission iam.serviceAccounts.create is required"
    - works after a while, when you can see it in the project dropdown in cloud console
  - billing account needs to be linked
    - set `billing_account` in the project resource block
    - CANNOT BE LINKED TO > 3 PROJECTS ON FREE TRIAL
      - Unlink the default 'first project' by disabling billing for that project in Billing Account -> Account management
    - using the default block to set `billing_account` didn't show up for some reason in `terraform plan`;
    - creating cloud bucket returned "error 403 billing account disabled"
    - try using remote module from google; no luck
  - if this doesn't work, must do this in console:
    - create project (could be from `gcloud projects create`)
    - link to billing account (must be on console)
    - record project name in `.env` somehow
  - [provisioner `local-exec`](https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec) can run bash commands
  - [`terraform-google-gcloud`](https://registry.terraform.io/modules/terraform-google-modules/gcloud/google/latest) is a terraform wrapper for gcloud
  - useful to programmatically enable `service usage` and `cloud resource manager` API, which are pre-requisites to enabling *other* APIs via terraform
  - those APIs are enabled automatically if a project is created via console
- `google_bigquery_job` for loading geojson as a table in our dataset
  - `Error creating Job: googleapi: Error 404: Not found: Dataset`???
  - need to set location here as well

### startup script woes

- `/etc/environment` accepts only simple assignment, i.e. `VAR=some_value`
- `/etc/profile.d/<some_file>.sh` accepts `export VAR=some_val`, and will be run on startup
- both should be acceptable to permanently set environment variables
- `/etc/environment` works; I only need simple assignments
- `make_*.py` not able to retrieve environment variables properly
  - if I SSH in to run them, then it's able to retrieve env vars...
- `sudo journalctl -u google-startup-scripts.service` to view log output of startup script
- if I source `/etc/environment`, it's as if I sourced a `.env`; without `export` it doesn't turn become environment, not without a re-login via something called `pam`

## Transform

- parquet files loaded from GCS do not need schema specification, even though docs may suggest otherwise

## Prefect

- cannot create flow run. failed to reach API at...
  - `prefect cloud login` with API key from cloud UI
  - set `PREFECT_API_URL` and `PREFECT_API_KEY` in environment of service-agent?
- agent needs to have docker installed, *regardless of what image I'm using*, obviously.
- storage block woes
  - The relative directory between `deploy.sh` (i.e. where you run `prefect deployment build`), `flow.py`, and `--storage-block` arg is **very delicate**
  - The most likely case: `deploy.sh` and `flow.py` are in the same folder. `--storage-block` *cannot have any subpath*. This directly affects how flow retrieval works.
  - Case 2: `deploy.sh` one level above `flow.py`, which is inside `proj-a`. `--storage-block` *must be set to `proj-a`*.
    - `... build proj-a/flow.py:flow_func`
    - everything in same dir as `deploy.sh` is uploaded, taking into account `.prefectignore`
    - the relative dir specified in `build` is then relative to the `--path` arg, if passed
    - cannot `build ./flow.py:flow_func` and then pass `--path=prefect-flow`; agent will then try to retrieve the flow code from a folder named `prefect-flow`, which doesn't exist
    - the maddening thing is that upload will go smoothly, creating the `--path` subdir in GCS; problem only occurs during retrieval
  - [see section on subpath](https://medium.com/the-prefect-blog/prefect-2-3-0-adds-support-for-flows-defined-in-docker-images-and-github-repositories-79a8797a7371#e748)
- passing credentials to this docker container from our GCE instance
  - mount `$HOME/.config/gcloud/application_default_credentials.json:/gcp/creds.json`
    - need to use absolute dir when mounting, unless we're in CLI and we're using `docker run`
  - set `--env GOOGLE_APPLICATION_CREDENTIALS=/gcp/creds.json`
  - needs `GOOGLE_CLOUD_PROJECT` during `blob-exists`
    - not getting it from `TF_VAR_project_id`?
    - never mind, storage client needs `project=` to be explicitly assigned
  - mounting ADC worked locally, but not on instance: `/gcp/creds.json is a directory`???
  - mount just the `$HOME/.config/gcloud/:/gcloud/`, then set env var for ADC:
    - `--env GOOGLE_APPLICATION_CREDENTIALS=/gcloud/application_default_credentials.json`
    - set `CLOUDSDK_CONFIG=/gcloud` will allow `gsutil`, `bq`, and `gcloud` to work as well
  - in order to use `$HOME`:
    - create the block via `.py`
    - run `make_infra.py` as part of prefect agent VM start-up
    - use f-string when specifying the volume
    - the infra block will then correctly mount the host instance cred directory
    - [gcloud startup script docs](https://cloud.google.com/compute/docs/instances/startup-scripts/linux#gcloud)
    - [terraform metadata startup docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance#metadata_startup_script)
    - startup-script can install docker, pip, prefect, but terraform is not able `prefect cloud login` without pre-existing secret
      - create secret with terraform
      - do not set default in `variables.tf`; have it take from local env `TF_VAR_prefect_api_key`
      - key stays in local environment, as well as remote state storage
- prior to creating the infra block, must connect with either remote server or cloud API endpoint
  - both requires `URL`
  - if we want to create the infra block during start-up, `URL` needs to be known before script upload
    - if remote prefect server is created as part of TF, `URL` can only be known after instance creation, via `network_interface.0.access_config.0.nat_ip`
    - how can the `startup-script` access this via prior to being uploaded to GCS?
  - do not upload script; if we keep the script in plain-text, we can use string interpolation to retrieve the newly created instance's IP
  - move away from prefect cloud; create the prefect server, attach the same service account
  - script in plain-text inside `main.tf` can reference all resource attributes
- deploy remote prefect server:
  - instance firewall must accept ipv4 range `0.0.0.0/0` for port `4200`
  - install pip, prefect
    - export PATH so `prefect` command is recognized
  - `prefect config set PREFECT_UI_API_URL=http://<EXTERNAL_IP>:4200/api` on server instance
    - must be `http`, not `https`
    - must have `compute.instances.get` project-level permission to retrieve its own external IP
    - `gcloud compute instances describe server --zone us-west1-b | grep natIP | cut -d: -f 2 | tr -d ' '` extracts external IP
  - `prefect config set PREFECT_API_URL="http://<EXTERNAL_IP>:4200/api"` on agent instance, *and* on local dev environment so that we can access the UI

### Authentication in container

How to authenticate the container app running on the compute engine instance? Mount the host instance's `$HOME/.config/gcloud` to the container's. Even if the `google_application_credentials.json` isn't present (because we haven't run `gcloud auth application-default`), that directory provides the permissions granted to the host instance's service account

Seems to use the host instance creds just fine without any volume mount

## dbt

### Integration with prefect

[Schedule dbt cloud with prefect](https://medium.com/the-prefect-blog/schedule-orchestrate-dbt-cloud-jobs-with-prefect-b64c3b7f2a02)

- dbt account id: last digits from account settings url

- API key: left nav > API access > view

  - save to local .env and create `DbtCloudCredentials` via `.py`, or create in UI

- create new job, and disable schedule so prefect can orchestrate (turn off run on schedule under trigger)

- copy job ID from URL

- code to run with prefect:

  ```py
  from prefect import flow

  from prefect_dbt.cloud import DbtCloudCredentials
  from prefect_dbt.cloud.jobs import trigger_dbt_cloud_job_run_and_wait_for_completion


  @flow
  def run_dbt_job_flow():
      trigger_dbt_cloud_job_run_and_wait_for_completion(
          dbt_cloud_credentials=DbtCloudCredentials.load("default"), job_id=JOB_ID
      )


  if __name__ == "__main__":
      run_dbt_job_flow()
  ```

### Requirements

- [`prefect-dbt`](https://github.com/PrefectHQ/prefect-dbt)
- PAID ACCOUNT TO FOR API ACCESS!
  - `prefect_dbt.cloud.exceptions.DbtCloudJobRunTriggerFailed: The API is not accessible to unpaid accounts`

### PIVOT TO MANUAL

As before, make the cloud dbt env, connect to repo, connect to bigquery, make the job and schedule it, instead of orchestrating via prefect

### Setup

- create service account
  - need bigquery.datasets.create on a project level
- commit and sync to branch before running command
- bigquery has `ROUND(expr, precision)` function
  - replace CAST()
- Seed `ward_id_lookup.csv` for dbt generic testing

## Viz

### Choropleth

Table needs to join with `city-wards.geojson` to get the `geometry` field

```sql
SELECT r.*, m.geometry
FROM service_calls_dev.requests_by_ward r
left join city_wards_map m
on r.ward_name = m.AREA_NAME
```

Seed the geojson, along with `ward_id_lookup.csv` for dbt generic testing

### geojson

How to automate loading the geojson as a table in bq?

- save in `data/`, and upload to gcs with terraform
- use `bq load`
  - part of terraform???
  - converted, newline delimited json to be part of base repo
  - `bq load` works, but `bigquery_job` does not; cannot find dataset, error 404
  - loading as external table works, but the format isn't friendly to geojson; data is in nested arrays
  - might be due to `-target` flag???
  - add `location = var.region` to specify job location
