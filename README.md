# Dbt Service Calls

Complementary to the [Toronto service calls data pipeline](https://github.com/vykuang/toronto-service-calls-2023)

## docs

Docs are self-hosted on gcloud app engine

## execution

1. Persistent VMs
  - easier to setup
  - low usage, potentially, i.e. waste of resources when not running models
2. Serverless compute, e.g. GCP cloud run, AWS fargate
  - runs containers on demand
  - removes them once complete
  - perfect for infrequent model compute, on a scheduled basis

### dbt on cloud run

cloud run jobs have several components required in order to run our containers

- Dockerfile to specify our image
- artifact registry where the image is stored
- service account with the necessary bigquery permissions to execute our dbt models
- enable the service APIs, e.g. bigquery, cloud run, registry
