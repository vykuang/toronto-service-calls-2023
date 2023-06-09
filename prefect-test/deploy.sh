#!/usr/bin/env bash
# coding: utf-8

# build deployment flow
prefect deployment build flows/log_flow.py:log_flow \
    -n log-flow \
    -q test \
    -p default-agent-pool \
    -ib docker-container/service-call-infra \
    -sb gcs/service-code-storage \
    --params='{"name": "service-data-lake"}' \
    --output log-flow_deployment \
    --apply

# manually starting a run
# prefect deployment run log-flow/log-flow
