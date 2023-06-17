#! /usr/bin/env sh
REGION=us-west1
gcloud beta run jobs execute quickstart \
    --region=$REGION
