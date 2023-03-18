#!/usr/bin/env bash
# coding: utf-8
poetry run python fetch.py \
    --bucket_name=$SERVICE_BUCKET \
    --test
    # --overwrite \