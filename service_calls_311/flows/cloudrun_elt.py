"""
Executed by prefect worker service, on same host as prefect server
similar paradigm to airflow's DockerOperator
"""
from pathlib import Path
import argparse
import os
from google.cloud import run_v2
from prefect import task, flow, get_run_logger

GOOGLE_CLOUD_PROJECT = os.getenv("TF_VAR_project_id")
os.environ["GOOGLE_CLOUD_PROJECT"] = GOOGLE_CLOUD_PROJECT
LOCATION = os.getenv("TF_VAR_region")
BUCKET = os.getenv("TF_VAR_data_lake_bucket")
DATASET = os.getenv("TF_VAR_bq_dataset")
ARTIFACT_REPO = os.getenv("TF_VAR_artifact_repo", "task-containers")

EXTRACT_JOB_ID = "extract"
LOAD_JOB_ID = "load"
TRANSFORM_JOB_ID = "dbt"


def execute_cloud_run(
    client: run_v2.JobsClient,
    job_id: str,
):
    """
    Given client and job_id, execute cloud run job
    """
    request = run_v2.RunJobRequest(
        name=f"projects/{GOOGLE_CLOUD_PROJECT}/locations/{LOCATION}/jobs/{job_id}",
    )
    op = client.run_job(request=request)
    return op.result()


def update_cloud_run(
    client: run_v2.JobsClient,
    job_id: str,
    bucket_name: str,
    dataset_name: str,
    year: str,
    overwrite: bool = False,
    test: bool = False,
):
    """
    Updates cloud run job config
    """
    # Initialize request argument(s)
    new_envs = [
        run_v2.EnvVar(name="var", value="newval"),
        run_v2.EnvVar(name="var2", value="newvalue2"),
        run_v2.EnvVar(name="var3", value="for kicks"),
    ]
    # the below boilerplate was necessary to properly encapsulate "new_envs"
    container = run_v2.Container(
        image=f"{LOCATION}-docker.pkg.dev/{GOOGLE_CLOUD_PROJECT}/{ARTIFACT_REPO}/agent:test",
        command=["python3"],
        args=["main.py"],
        env=new_envs,
    )
    task_template = run_v2.TaskTemplate(
        containers=[container],
        max_retries=3,
    )
    execution_template = run_v2.ExecutionTemplate(
        task_count=1,
        template=task_template,
    )
    job = run_v2.Job(
        name=f"projects/{GOOGLE_CLOUD_PROJECT}/locations/{LOCATION}/jobs/{job_id}",
        template=execution_template,
    )
    # job.template.template.max_retries = 3
    # job.template.template.containers.env = envs

    # instantiate updatejobrequest
    request = run_v2.UpdateJobRequest(job=job)

    # send the request
    operation = client.update_job(request=request)

    print("Waiting for operation to complete...")

    response = operation.result()

    # # Handle the response
    print(response)


@task
def extract(
    client: run_v2.JobsClient,
    bucket_name: str,
    year: str = "2020",
    overwrite: bool = False,
    test: bool = False,
):
    """
    execute extract on cloud run
    """
    update_cloud_run(
        client=client,
        job_id=EXTRACT_JOB_ID,
        bucket_name=bucket_name,
        year=year,
        overwrite=overwrite,
        test=test,
    )
    execute_cloud_run(client=client, job_id=EXTRACT_JOB_ID)


@task
def load(
    client: run_v2.JobsClient,
    dataset_name: str,
    year: str = "2020",
    overwrite: bool = False,
    test: bool = False,
):
    """
    load gcs dataset onto bigquery via cloud run
    """
    update_cloud_run(
        client=client,
        job_id=LOAD_JOB_ID,
        dataset_name=dataset_name,
        year=year,
        overwrite=overwrite,
        test=test,
    )
    execute_cloud_run(client=client, job_id=LOAD_JOB_ID)


@task
def transform(
    client: run_v2.JobsClient,
    dataset_name: str,
    year: str = "2020",
    test: bool = False,
):
    """
    transform bq dataset with dbt via lcoud run
    """
    update_cloud_run(
        client=client,
        job_id=TRANSFORM_JOB_ID,
        dataset_name=dataset_name,
        year=year,
        test=test,
    )
    execute_cloud_run(client=client, job_id=TRANSFORM_JOB_ID)


@flow
def elt_service_calls(
    bucket_name: str,
    dataset_name: str,
    year: str,
    overwrite: bool = False,
    test: bool = False,
):
    """
    Extracts CSV as parquets on gcs, loads into bigquery dataset,
    and transform with dbt

    Parameters
    ----------
    bucket_name: str
        name of bucket in GCS
    dataset_name: str
        name of dataset in bigquery
    year: str
        year for which to extract the service call request records
    overwrite: bool
        if true, overwrite existing parquet/dataset
    test: bool
        if true, load only a small subset onto bigquery
    """
    logger = get_run_logger()
    logger.info(
        f"Beginning extract with env vars:\nproject ID: {GOOGLE_CLOUD_PROJECT}\nlocation: {LOCATION}"
    )
    client = run_v2.JobsClient()
    res_ex = execute_cloud_run(
        client,
        "extract",
        bucket_name=bucket_name,
        year=year,
        overwrite=overwrite,
        test=test,
    )
    logger.info(res_ex)
    res_load = execute_cloud_run(client, "load-bq")
    logger.info(res_load)
    res_transform = transform()
    logger.info(res_transform)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="Fetch311Records",
        description="Fetch 311 service records and stores as parquet",
        epilog="DE zoomcamp project",
    )
    opt = parser.add_argument
    opt(
        "-b",
        "--bucket_name",
        type=str,
        default=BUCKET,
        help="GCS bucket to store the CSV and parquet files",
    )
    opt(
        "-d",
        "--dataset_name",
        type=str,
        default=DATASET,
        help="bigquery dataset name in which to load table",
    )
    opt("-y", "--year", default="2020", type=str)
    opt(
        "-O",
        "--overwrite",
        action="store_true",
        default=False,
        help="If specified, overwrites existing parquet file",
    )
    opt(
        "-t",
        "--test",
        action="store_true",
        default=False,
        help="If specified, only reads small section of csv",
    )
    args = parser.parse_args()
    elt_service_calls(
        bucket_name=args.bucket_name,
        dataset_name=args.dataset_name,
        year=args.year,
        overwrite=args.overwrite,
        test=args.test,
    )
