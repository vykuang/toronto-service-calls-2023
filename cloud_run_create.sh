#! /usr/bin/env sh
PROJECT_ID=service-calls-dev
REGION=us-west1
gcloud beta run jobs create \
    --image us-west1-docker.pkg.dev/$PROJECT_ID/task-containers/agent:test \
    --tasks 5 \
    --set-env-vars SLEEP_MS=10000 \
    --set-env-vars FAIL_RATE=0.5 \
    --max-retries 5 \
    --region $REGION \
    --project=$PROJECT_ID
