import os
from flows.extract_load import extract_load_service_calls
from prefect.deployments import Deployment
from prefect.filesystems import GCS
from prefect.infrastructure.docker import DockerContainer
from prefect.server.schemas.schedules import CronSchedule

BUCKET = os.getenv("TF_VAR_data_lake_bucket")
DATASET = os.getenv("TF_VAR_bq_dataset")
storage = GCS.load("service-code-storage")
container = DockerContainer.load("service-call-infra")
schedule = CronSchedule(cron="0 0 1 * *")
params = {
    "bucket_name": BUCKET,
    "dataset_name": DATASET,
    "year": 2023,
    "overwrite": True,
    "test": False,
}
# debug to see whether correct env vars are retrieved
print(f"Bucket: {BUCKET}\ndataset: {DATASET}")
deployment = Deployment.build_from_flow(
    flow=extract_load_service_calls,
    name="extract-load",
    work_queue_name="service-calls",
    output="service-pipeline-deployment.yaml",
    storage=storage,
    infrastructure=container,
    schedule=schedule,
    parameters=params,
)
deployment.apply()
