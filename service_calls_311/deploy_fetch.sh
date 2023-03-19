#!/usr/bin/env bash
# coding: utf-8
poetry run prefect deployment build ./fetch.py:extract_service_calls \
    -n extract-service-calls \
    -q service-calls \
    -p default-agent-pool \
    --params='{"bucket_name": "service-calls-data-lake", "year": "2023"}' \
    --output web-gcs-deployment \
    --skip-upload \
    --apply

poetry run prefect deployment run extract-service-calls/extract-service-calls
poetry run prefect agent start -p default-agent-pool --run-once