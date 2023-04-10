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

## Transform

- parquet files loaded from GCS do not need schema specification, even though docs may suggest otherwise

## Prefect

- cannot create flow run. failed to reach API at...
    - `prefect cloud login` with API key from cloud UI
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
