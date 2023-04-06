#!/usr/bin/env bash
# coding: utf-8
poetry run python extract_load.py \
    --bucket_name=$TF_VAR_data_lake_bucket \
    --dataset_name=$TF_VAR_bq_dataset \
    --year=2023 \
    --test
    # --overwrite \
