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

### dockerfile

This will be submitted to cloud build, and stored in artifact registry. Include all dependencies for our flows

To start, use one dockerfile for extract, load, and dbt?

### proof of concept

- dockerfile with all dependencies
  - use `poetry export` and `pip install -r requirements.txt`
- create artifacts repo in `gcr.io` domain
  - `us-west1-docker.pkg.dev/service-calls-dev/task-containers`
- shell script to submit to cloud build and artifacts
  - create `cloudbuild.yaml` [from this template which uses user substitutions](https://cloud.google.com/artifact-registry/docs/configure-cloud-build#docker)
  - `gcloud builds submit --config=cloudbuild.yaml \  --substitutions=_LOCATION="us-west1",_REPOSITORY="task-containers",_IMAGE="my-image" .`
  - will use the Dockerfile and `.yaml` in the same dir running the shell script
  - pay attention to `.dockerignore` and `.gcloudignore`
    - `gcloud` will by default upload entire dir to temp gcs bucket; use `.gcloudignore`
    - from uploaded files, docker will refer to `.dockerignore`
- py script to trigger cloud run using the artifacts image
