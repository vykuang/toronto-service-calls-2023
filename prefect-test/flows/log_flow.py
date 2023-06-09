import sys
import prefect
from prefect import flow, task, get_run_logger
from google.cloud import storage, bigquery
from utilities import AN_IMPORTED_MESSAGE

import os

GOOGLE_CLOUD_PROJECT = os.getenv("TF_VAR_project_id")
os.environ["GOOGLE_CLOUD_PROJECT"] = GOOGLE_CLOUD_PROJECT
LOCATION = os.getenv("TF_VAR_region")
BUCKET = os.getenv("TF_VAR_data_lake_bucket")
DATASET = os.getenv("TF_VAR_bq_dataset")


@task
def log_task(name):
    logger = get_run_logger()
    logger.info("Hello %s!", name)
    logger.info("Prefect Version = %s 🚀", prefect.__version__)
    logger.debug(AN_IMPORTED_MESSAGE)


@task
def list_my_blobs(
    project_id: str = GOOGLE_CLOUD_PROJECT,
    bucket_name: str = BUCKET,
    prefix: str = "code/",
    delimiter=None,
):
    logger = get_run_logger()
    client = storage.Client(project=project_id)
    blobs = client.list_blobs(
        bucket_or_name=bucket_name, prefix=prefix, delimiter=delimiter
    )
    for blob in blobs:
        logger.info(blob.name)


@task
def list_my_datasets(
    project_id: str = GOOGLE_CLOUD_PROJECT,
    dataset_id: str = DATASET,
):
    """
    Creates a bq client and list tables within that dataset
    Tests permissions
    """
    logger = get_run_logger()
    logger.info(f"dataset: {dataset_id}")
    client = bigquery.Client(project=project_id)
    for table in client.list_tables(dataset=dataset_id):
        logger.info(f"table name: {table.table_id}")


@flow()
def log_flow(name: str):
    log_task(name)
    list_my_blobs()
    list_my_datasets()


if __name__ == "__main__":
    name = sys.argv[1]
    log_flow(name)
