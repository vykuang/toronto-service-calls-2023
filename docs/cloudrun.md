# GCP Cloud Run

- Services - run code that respond to events or HTTP requests
  - HTTPS endpoint
  - auto scaling
  - cloud IAM/ingress setting/authenticated user
  - scale to zero
  - non-persistent filesystem; integrate with cloud storage for persistence
  - used for
    - website/web apps, access DB
    - REST API or private microservices over HTTP
    - receiving pub/sub push msgs
- Jobs - runs a script and exits when complete; allows parallel instances, i.e. array jobs
  - used for
    - script to migrate db
    - array job, processing multiple files the same way
    - scheduled jobs, uploading/sending files
  - integrate with cloud storage/bigquery
  - container logs ingested by Cloud Logging
  - linked to service account, used to authenticate with other GCP APIs
    - solves dbt docker authentication
  - continuous delivery; configure to automatically deploy new commits
  - **NOT SET UP FOR RUNTIME PARAMETRIZATION**
    - must *update* with desired arguments before job execution
    - having a hard time finding out how to do so with python client

## cloud run jobs - a new framework

Existing framework sends flows to prefect agent running on a persistent VM. The deployment is specified to build the environment infra by pulling a docker image that includes all dependencies, and running the flow in that container

Cloud run allows prefect to skip all that. Bake the script inside our images, upload to artifact registry, and have prefect orchestrate the cloud run jobs, without needing to know what's inside the flows, or what infra the flows need.

```py
from prefect_gcp.cloud_run import CloudRunJob

@flow
def cloud_run_job_flow():
	job = CloudRunJob(
		image="us-docker.pkg.dev/path/to/container:tag",
		region="",
		command=["override", "entrypoint"],
	)
	return job.run()
```

Or invoke cloud run jobs via the [gcp-python client](https://cloud.google.com/python/docs/reference/run/latest/google.cloud.run_v2.services.jobs.JobsClient#google_cloud_run_v2_services_jobs_JobsClient_create_job), as I've already done for gcs and bq

prefect polling service can run on same node instance as the server, as it's only responsible for invoking cloud run jobs

Alternatively we can use cloud run job as another type of infrastructure block, replacing `DockerContainer`. We can run a `worker`, a "lightweight polling service", on the same node as our server, to send the flow to cloud run for execution. Prefect must be installed as a dependency in the docker image

### worker vs agent

worker offers more options in execution environment. Work pools and  workers are typed according to their execution environment; deploying flows to certain work pools guarantee the execution environment. Agents V2, beta.

Projects are closely related. Conceptually it specifies what users do when creating deployments, and what workers do before it executes deployment. Concretely it is a directory of files defining flows, pkgs, and other dependencies

### cloud run with python

Create job

```py
from google.cloud import run_v2

def sample_create_job():
    # Create a client
    client = run_v2.JobsClient()

    # init request args
    job = run_v2.Job()
    job.template.template.max_retries = 1187

    request = run_v2.CreateJobRequest(
      parent="projects/my-project/locations/us-west1",
      job=job,
      job_id="job-somesixdigitnum", # full: {parent}/jobs/{job_id}
    )

    # make request
    op = client.create_job(request=request)
    resp = op.result()

    # handle response
    print(response)
```

### terraform

create jobs with terraform

- extract from open data onto gcs
- load from gcs onto bq
- transform with dbt

extract and load can share dependencies, with different entrypoints. transform will use the base dbt-bigquery image, with our dbt model repo baked in?

Execute job with python library within flow by invoking each cloud run job

```py
from google.cloud import run_v2

def sample_run_job():
	 # Create a client
    client = run_v2.JobsClient()

	# init request args
	request = run_v2.RunJobRequest(
		name="full_job_name", # projects/{project}/loc/{loc}/jobs/{job_id}
	)

	# make run request
	op = client.run_job(request=request)
	run_resp = op.result()

	# handle response
	print(response)
```

## set up

- enable cloud run admin API - run.googleapis.com
- service account with roles for
  - cloud run admin - create/update/delete/run jobs
  - invoker - run
  - viewer - view, list
- enable artifact registry

### job config

- image url source (from artifact registry)
- name
- region
- entrypoint command
- entrypoint args
- resources - mem, cpu, timeout, parallelism
- env variables and secrets, mount as vol or expose as env var
- attached service account

### update job

in order to parametrize our jobs, we need to update jobs at runtime with the passed arguments as new environment variables with `UpdateJobRequest`

```py
def sample_update_job(job_id):
    """
    Not from official docs, just what I could hack together
    """
    # Create a client
    client = run_v2.JobsClient()

    # Initialize request argument(s)
    new_envs = [
        run_v2.EnvVar(name="var", value="newval"),
        run_v2.EnvVar(name="var2", value="newvalue2"),
        run_v2.EnvVar(name="var3", value="for kicks"),
    ]
    # the below boilerplate was necessary to properly encapsulate "new_envs"
    container = run_v2.Container(
        image=f"us-west1-docker.pkg.dev/{GOOGLE_CLOUD_PROJECT}/task-containers/agent:test",
        command=["python3"],
        args=["main.py"],
        env=new_envs
    )
    task_template = run_v2.TaskTemplate(
        containers=[container],
        max_retries=4,
    )
    execution_template = run_v2.ExecutionTemplate(
        task_count=2,
        template=task_template,
    )
    job = run_v2.Job(
        name=f"projects/{GOOGLE_CLOUD_PROJECT}/locations/{LOCATION}/jobs/{job_id}",
        template=execution_template
    )
    job.template.template.max_retries = 3
    # job.template.template.containers.env = envs

    # instantiate updatejobrequest
    request = run_v2.UpdateJobRequest(
        job=job,
    )

    # # send the request
    operation = client.update_job(request=request)

    print("Waiting for operation to complete...")

    response = operation.result()

    # # Handle the response
    print(response)
```

### dockerfile

This will be submitted to cloud build, and stored in artifact registry. Include all dependencies for our flows

To start, use one dockerfile for extract, load, and dbt?

### proof of concept

- dockerfile with all dependencies
  - use `poetry export` and `pip install -r requirements.txt`
  - `poetry export -o dockerfiles/requirements.txt --only=main`
- create artifacts repo in `gcr.io` domain
  - `us-west1-docker.pkg.dev/service-calls-dev/task-containers`
  - `gcloud auth configure-docker us-west1-docker.pkg.dev` to enable pulling from newly created repo
  
  ```shell
    gcloud artifacts repositories create task-containers-default \
      --repository-format=docker \
      --location=us-west1 \
      --description="default task container repo" \
      --async \
      --disable-vulnerability-scanning
    ```
- shell script to submit to cloud build and artifacts
  - create `cloudbuild.yaml` [from this template which uses user substitutions](https://cloud.google.com/artifact-registry/docs/configure-cloud-build#docker)
  - `gcloud builds submit --config=cloudbuild.yaml \  --substitutions=_LOCATION="us-west1",_REPOSITORY="task-containers",_IMAGE="my-image" .`
  - will use the Dockerfile and `.yaml` in the same dir running the shell script
  - pay attention to `.dockerignore` and `.gcloudignore`
    - `gcloud` will by default upload entire dir to temp gcs bucket; use `.gcloudignore`
    - from uploaded files, docker will refer to `.dockerignore`
    - does it only use `main.py`? no it depends on the Dockerfile `ENTRYPOINT`
- py script to trigger cloud run using the artifacts image

### production

- each task, (extract, load, transform) will have individual job-id
  - created at setup time, by terraform?
- ~~no clear cut way of updating job environment variables via python client~~
  - no analog to `gcloud run update-job`
  - prefect has API to allow new entrypoint, command, and ENVs
    - they create new jobs, run immediately, then cleanup after
  - we can do that as well?
  - or just use `prefect-gcp`?
- `UpdateJobRequest` figured out; see above code block
  - Needs string literals, otherwise trips with `bad built-in operation` error when it sees variables
  - solution: cast to `str()`
  - I imagine the same was true when I tried to create sequence of `EnvVar` with list comprehension
- `EnvVar` will not change, set with terraform
  - if updated, *all prior env vars* will be replaced with new set of env vars
  - if `env` was not specified, it will replaced with nothing
  - need to rethink how env vars are set, and whether they're needed
- `Container.args` will be updated depending on task parameters
  - only update `args`; leave `command` to use default entrypoint
  - if we do not specify `command`, it will be as if we supplied an empty command
  - again, *if we do not specify env while updating args, envs will be wiped clean*
- how to pass `src_uris` from `extract` to `load` cloud run?
  - return as an env var?
    - works in notebook context, but unable to retrieve in external shell
  - assign a temporary bucket location to pick up parquets from, and cleanup after?
  - run both in the same container, no need to persist anything
  - downside is we lost prefect logging in between
    - rely on cloud logging to retrieve cloud run outputs?
- how to package the dbt-project folder into the docker image?
  - need to include the folder as a subfolder in the service project root
  - how will that affect git?
    - add `dbt-project/` in main project's .gitignore
    - `dbt-project/` is its own git
    - `git clean -dfx` will remove all items in `.gitignore`
    - `git clone` will also not have `dbt-project/`
      - add instruction to `git clone dbt-project.git` after `cd main-repo`?
  - use `git subtree`???
    - add as a remote first: `git remote add -f alias-for-remote <url-to-subtree-repo.git>`
    - ensure current staging is clean, i.e. no unstaged edits
    - add as a subtree: `git subtree add --prefix local-dir-for-subtree alias-for-remote remote-branch --squash`
      - this copies the repo to local directory
    - update from upstream with
      - `git fetch alias-for-remote main`
      - `git subtree pull --prefix local-dir-subtree alias-for-remote main --squash`
- Organizing variables
  - build time:
    - PROJ_ID
    - BQ_DATASET
    - GCS_BUCKET
  - run time:
    - year
    - overwrite
    - test

### override job config for specific execution

[This allows programmatic execution of jobs from code](https://cloud.google.com/run/docs/execute/jobs#override-job-configuration)

Even though it's still pre-GA, this means we don't have to update job config before each execution. CLI:

```bash
gcloud beta run jobs execute JOB_NAME \
     --args ARGS \
     --update-env-vars KEY=VALUE>,KEY_N=VALUE_N \
     --tasks TASKS \
     --task-timeout TIMEOUT
```

- Requires upgrade of gcloud SDK
- rebuild image to fix "unexpected keyword: loglevel" error in extract_load.py
