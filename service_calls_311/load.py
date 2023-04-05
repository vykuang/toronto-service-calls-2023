#!/usr/bin/env python
# coding: utf-8

from pathlib import Path
from google.cloud import bigquery
import argparse
from prefect import flow, task, get_run_logger


@task(tags=["load"])
def load_bigquery(src_uris: str, dest_table: str, location: str = "us-west1"):
    """
    Loads file from URIs to bigquery table

    Parameters
    ----------
    src_uris: str
        URIs of data files to be loaded; in format gs://<bucket_name>/<object_name_or_glob>.
    dest_table: str
        Table into which data is to be loaded

    Returns
    -------
    LoadJob class object
    """
    logger = get_run_logger()
    client = bigquery.Client(
        location=location,
        # project=project_id # infer from env
        # credentials=creds # not needed if instance is already credentialled
    )
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.PARQUET,
        time_partitioning=bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY, field="creation_datetime"
        ),
        clustering_fields=["service_request_type", "ward_id"],
    )
    load_job = client.load_table_from_uri(
        src_uris,
        dest_table,
        job_config=job_config,
        project=GCP_PROJECT_ID,
    )
    logger.info(f"Job creation time: {load_job.created}")
    load_job.add_done_callback(
        lambda x: logger.info(
            f"Job duration: {load_job.ended - load_job.started}\nState: {load_job.state}"
        )
    )
    load_job.result(timeout=3.0)
    return load_job


@flow
def load(src_uris: str, dest_table: str):
    """
    Loads parquets from GCS to bigquery

    Parameters
    ----------
    src_uris: str
        URIs of data files to be loaded; in format gs://<bucket_name>/<object_name_or_glob>.
    dest_table: str
        Table into which data is to be loaded. <project_id>.<dataset_id>.<table_name>

    Returns
    -------
    None
    """
    logger = get_run_logger()
    logger.info(f"loading from {src_urs} into {dest_table}")
    load_job = load_bigquery(src_uris, dest_table)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="Load311Records",
        description="Load service record parquets from GCS into bigquery",
        epilog="DE zoomcamp project",
    )
    opt = parser.add_argument
    opt(
        "-s",
        "--source_uris",
        type=str,
        required=True,
        help="cloud storage URIs for the parquets, e.g. gs://data_lake/*",
    )
    # opt(
