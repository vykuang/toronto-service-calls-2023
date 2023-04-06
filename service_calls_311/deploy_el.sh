#!/usr/bin/env bash
# coding: utf-8

# build deployment flow
poetry run prefect deployment build ./fetch.py:extract_load_service_calls \
    -n extract-load \
    -q service-calls \
    -p default-agent-pool \
    --params='{"bucket_name": "$TF_VAR_data_lake_bucket", "dataset_name": "$TF_VAR_bq_dataset", "year": "2023"}' \
    --output web-gcs-deployment \
    --skip-upload \
    --apply

# manually starting a run
poetry run prefect deployment run extract-load/extract_load_service_calls
# starting a local agent to execute the manual run
poetry run prefect agent start -p default-agent-pool --run-once
