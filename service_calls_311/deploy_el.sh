#!/usr/bin/env bash
# coding: utf-8
set -o allexport
source .env
set +o allexport
# build deployment flow
poetry run prefect deployment build ./extract_load.py:extract_load_service_calls \
    -n extract-load \
    -q service-calls \
    -p default-agent-pool \
    -ib docker-container/service-call-infra \
    -sb gcs/service-code-storage \
    --path prefect-flow \
    --params='{"bucket_name": "service-data-lake", "dataset_name": "service_calls_models", "year": "2023"}' \
    --output web-gcs-deployment \
    --apply

# manually starting a run
# poetry run prefect deployment run extract-load-service-calls/extract-load
# starting a local agent to execute the manual run
# poetry run prefect agent start -p default-agent-pool --run-once
