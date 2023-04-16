"""
Creates the prefect block via code
Easier to set env vars for the container rather than UI
Run this script on the prefect agent instance so that $HOME gets
the correct directory to mount the credential file
"""
from prefect.infrastructure.docker import DockerContainer

# from dotenv import load_dotenv
# from pathlib import Path
import os

# env_file = Path("../../.env").resolve()
# load_dotenv(env_file)

GOOGLE_CLOUD_PROJECT = os.getenv("TF_VAR_project_id")
LOCATION = os.getenv("TF_VAR_region")
BUCKET = os.getenv("TF_VAR_data_lake_bucket")
DATASET = os.getenv("TF_VAR_bq_dataset")
HOME = os.getenv("HOME")

block_name = "service-call-infra"
gcp_dir = "/gcloud"
infra_block = DockerContainer(
    name=block_name,
    image="vykuang/service-calls:base-pip-v2",
    env={
        "TF_VAR_project_id": GOOGLE_CLOUD_PROJECT,
        "TF_VAR_region": LOCATION,
        "TF_VAR_data_lake_bucket": BUCKET,
        "TF_VAR_bq_dataset": DATASET,
        "GOOGLE_CLOUD_PROJECT": GOOGLE_CLOUD_PROJECT,
        "GOOGLE_APPLICATION_CREDENTIALS": f"{gcp_dir}/application_default_credentials.json",
    },
    image_pull_policy="ALWAYS",
    auto_remove=False,
    volumes=[
        f"{HOME}/.config/gcloud:{gcp_dir}",
    ],
)

infra_block.save(
    name=block_name,
    overwrite=True,
)
