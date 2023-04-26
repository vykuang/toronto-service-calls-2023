from prefect.filesystems import GCS
import os


GOOGLE_CLOUD_PROJECT = os.getenv("TF_VAR_project_id")
BUCKET = os.getenv("TF_VAR_data_lake_bucket")


block = GCS(
    bucket_path=f"{BUCKET}/code/",
    project=GOOGLE_CLOUD_PROJECT,
)
block.save(
    name="service-code-storage",  # no underscore
    overwrite=True,
)
