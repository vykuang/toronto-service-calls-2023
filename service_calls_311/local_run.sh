#!/usr/bin/env bash
# coding: utf-8
ADC=~/.config/gcloud/application_default_credentials.json
docker run \
    -it \
    -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys.json \
    -v ${ADC}:/tmp/keys.json:ro \
    --mount type=bind,source="${PWD}",target=/service \
    --entrypoint=bash \
    vykuang/service-calls:base
