#!/usr/bin/env bash
# coding: utf-8
set -o allexport
source .env
set +o allexport
# build deployment flow
poetry run prefect deployment build flows/extract_load.py:extract_load_service_calls \
    -n extract-load \
    -q service-calls \
    -p default-agent-pool \
    --infra process \
    -sb gcs/service-code-storage \
    --params='{"bucket_name": "service-data-lake", "dataset_name": "service_calls_models", "year": "2022"}' \
    --output web-gcs-deployment \
    --apply
    # --path prefect-flow \

# manually starting a run
# poetry run prefect deployment run extract-load-service-calls/extract-load
# starting a local agent to execute the manual run
# poetry run prefect agent start -p default-agent-pool --run-once
