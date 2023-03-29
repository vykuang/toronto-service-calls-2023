#!/usr/bin/env python
# coding: utf-8

from pathlib import Path
from google.cloud import bigquery

import argparse
from prefect import flow, task, get_run_logger


@task
def load_bigquery():
    """
    Loads file from URIs to bigquery table
    """
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.PARQUET,
        time_partitioning=bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY, field="creation_datetime"
        ),
        clustering_fields=["Service_Request_Type", "ward_id"],
    )
    load_job = ""


@flow
def load():
    """
    Loads parquets from GCS to bigquery
    """
    client = bigquery.Client()


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
