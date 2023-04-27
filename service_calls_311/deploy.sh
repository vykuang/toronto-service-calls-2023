#!/usr/bin/env bash
# coding: utf-8

# build deployment flow
prefect deployment build flows/extract_load.py:extract_load_service_calls \
    -n extract-load \
    -q service-calls \
    -p default-agent-pool \
    -ib docker-container/service-call-infra \
    -sb gcs/service-code-storage \
    --cron "0 0 1 * *" \
    --params='{"bucket_name": "service-data-lake", "dataset_name": "service_calls_models", "year": "2023", "overwrite": "True", "test": "False"}' \
    --output service-pipeline-deployment \
    --apply

# manually starting a run
# prefect deployment run extract-load-service-calls/extract-load
# starting a local agent to execute the manual run
# prefect agent start -p default-agent-pool --run-once
