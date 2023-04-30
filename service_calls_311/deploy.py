#! /usr/bin/env python

import os
import argparse
from flows.extract_load import extract_load_service_calls
from prefect.deployments import Deployment, run_deployment
from prefect.filesystems import GCS
from prefect.infrastructure.docker import DockerContainer
from prefect.server.schemas.schedules import CronSchedule

BUCKET = os.getenv("TF_VAR_data_lake_bucket")
DATASET = os.getenv("TF_VAR_bq_dataset")


def deploy(apply: bool = True, run: bool = False):
    deploy_name = "extract-load"
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
    if apply:
        deployment.apply()
    if run:
        response = run_deployment(
            name=f'{extract_load_service_calls.__name__.replace("_","-")}/{deploy_name}'
        )
        print(response)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    opt = parser.add_argument
    opt(
        "-a",
        "--apply",
        help="applies the deployment if specified",
        action="store_true",
        default=True,
    )
    opt(
        "-r",
        "--run",
        help="manually runs the applied deployment if specified",
        action="store_true",
        default=False,
    )
    args = parser.parse_args()
    deploy(apply=args.apply, run=args.run)
