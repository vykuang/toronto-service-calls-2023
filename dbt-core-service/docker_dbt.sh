#! /usr/bin/env sh
docker run \
--network=host \
--mount type=bind,source=/home/kohada/dbt-core-service-calls,target=/usr/app \
--mount type=bind,source=/home/kohada/dbt-core-service-calls/profiles.yml,target=/root/.dbt/profiles.yml \
--mount type=bind,source=/home/kohada/.config/gcloud/service-dbt.json,target=/usr/app/auth/keyfile.json \
ghcr.io/dbt-labs/dbt-bigquery:1.5.0 \
$1 --target=$2
