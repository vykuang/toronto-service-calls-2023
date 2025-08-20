from prefect import flow
from prefect_gcp.workers.cloud_run import CloudRunWorker, CloudRunWorkerVariables, CloudRunWorkerJobConfiguration

config = CloudRunWorkerJobConfiguration(
    region='us=west1',
    job_body={
        "apiVersion": "run.googleapis.com/v1", 
        "kind": "Job", 
        "metadata": { "name": "job-name", 
        "spec": {
            "containers": [
                {"image": "us-west1-docker.pkg.dev/to-service-311/task-containers-default/worker_extraction_load",
                 "args": "", 
                 "resources": {
                     "limits": {
                         "cpu": "1",
                         "memory": "2Gi"}, 
                         "requests": { "cpu": "{{ cpu }}", "memory": "{{ memory }}" } 
                    } 
                } ], 
                "timeoutSeconds": "",
                "serviceAccountName": "service-agent@to-service-311.iam.gserviceaccount.com" } } , 
                "metadata": { "annotations": ""},
                "keep_job": ""}
    # Add any other parameters or overrides as needed
)
# config.prepare_for_flow_run('sample-gcloud-run-flow')
vars = CloudRunWorkerVariables(
    region='us=west1',
    image='us-west1-docker.pkg.dev/to-service-311/task-containers-default/worker_extraction_load',
    service_account_name='service-agent@to-service-311.iam.gserviceaccount.com',
)
# config.prepare_for_flow_run()
@flow
def trigger_cloud_run_job_flow():
    # Load credentials and define CloudRunJob block as described above
    # ...
    
    result = CloudRunWorker(
        # job_configuration=config
        vars,
    ).run(
        'brave-bird',
        config,
    )
    return result

trigger_cloud_run_job_flow()