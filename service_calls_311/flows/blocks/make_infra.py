"""
Creates the prefect block via code
Easier to set env vars for the container rather than UI
"""
from prefect.infrastructure.docker import DockerContainer

import os


GOOGLE_CLOUD_PROJECT = os.getenv("TF_VAR_project_id")
LOCATION = os.getenv("TF_VAR_region")
BUCKET = os.getenv("TF_VAR_data_lake_bucket")
DATASET = os.getenv("TF_VAR_bq_dataset")
HOME = os.getenv("HOME")

block_name = "service-call-infra"
infra_block = DockerContainer(
    name=block_name,
    image="vykuang/service-calls:prod-latest",
    env={
        "TF_VAR_project_id": GOOGLE_CLOUD_PROJECT,
        "TF_VAR_region": LOCATION,
        "TF_VAR_data_lake_bucket": BUCKET,
        "TF_VAR_bq_dataset": DATASET,
        "GOOGLE_CLOUD_PROJECT": GOOGLE_CLOUD_PROJECT,
    },
    image_pull_policy="ALWAYS",
    auto_remove=False,
)

infra_block.save(
    name=block_name,
    overwrite=True,
)
