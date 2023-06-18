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


@task
def extract():
    """
    execute extract on cloud run
    """
    client = run_v2.JobsClient()
    request = run_v2.RunJobRequest(
        name=f"projects/{GOOGLE_CLOUD_PROJECT}/locations/{LOCATION}/jobs/{job_id}",
    )
    op = client.run_job(request=request)
    return op.result()


@task
def load():
    """
    load gcs dataset onto bigquery via cloud run
    """


@task
def transform():
    """
    transform bq dataset with dbt via lcoud run
    """


@flow
def service_calls_elt(
    year: str,
    overwrite: bool = False,
    test: bool = False,
):
    """ """
    logger = get_run_logger()
    logger.info(
        f"Beginning extract with env vars:\nproject ID: {GOOGLE_CLOUD_PROJECT}\nlocation: {LOCATION}"
    )
    res_ex = extract()
    logger.info(res_ex)
    res_load = load()
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
    service_calls_elt(
        year=args.year,
        overwrite=args.overwrite,
        test=args.test,
    )
