#!/usr/bin/env bash
# coding: utf-8
ADC=$HOME/.config/gcloud/application_default_credentials.json
docker run \
    -it \
    --env-file .env \
    -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys.json \
    --mount type=bind,src=${ADC},dst=/tmp/keys.json,readonly \
    --mount type=bind,src=${PWD},dst=/service \
    --entrypoint ./el.sh \
    vykuang/service-calls:base
    # --entrypoint=bash \
        # poetry shell
    # --mount type=bind,source="${PWD}",target=/service \
