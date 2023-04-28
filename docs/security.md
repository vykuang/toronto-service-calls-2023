# Security

Security is enforced in this project by practicing principle of least privilege when assigning permissions to service accounts and storing sensitive credentials in GCP's secret manager, e.g. Prefect API key

[GCP blogpost on this topic](https://cloud.google.com/blog/products/identity-security/dont-get-pwned-practicing-the-principle-of-least-privilege)

## secrets manager

Stores credentials from third-party apps that we need to authenticate with, e.g. prefect API key

## Motivation

Using secrets manager is preferred over environment variables for the following reasons

- resistant to **directory traversal** attacks
- resistant to debug endpoints, or dependencies which log process environment
- when syncing secrets to another data store, no longer need to consider access controls of that data store

## Implementation on GCP secrets manager

[quick start guide](https://cloud.google.com/secret-manager/docs/create-secret-quickstart#secretmanager-quickstart-gcloud)

Required permission to access: `roles/secretmanager.secretAccessor`. This permission can be granted at these levels, from lowest to highest:

- secret - access only the one secret
- project - all secrets in this project
- folder - all projects
- organization - all folders

Providing accessor permission for one secret:

```bash
gcloud secrets add-iam-policy-binding secret-id \
    --member="member" \
    --role="roles/secretmanager.secretAccessor"
```

### python

[code sample from docs](https://cloud.google.com/secret-manager/docs/reference/libraries#client-libraries-usage-python)

```py
# Import the Secret Manager client library.
from google.cloud import secretmanager

# GCP project in which to store secrets in Secret Manager.
project_id = "YOUR_PROJECT_ID"

# ID of the secret to create.
secret_id = "YOUR_SECRET_ID"

# Create the Secret Manager client.
client = secretmanager.SecretManagerServiceClient()

# Build the parent name from the project.
parent = f"projects/{project_id}"

# Create the parent secret.
secret = client.create_secret(
    request={
        "parent": parent,
        "secret_id": secret_id,
        "secret": {"replication": {"automatic": {}}},
    }
)

# Add the secret version.
version = client.add_secret_version(
    request={"parent": secret.name, "payload": {"data": b"hello world!"}}
)

# Access the secret version.
response = client.access_secret_version(request={"name": version.name})

# Print the secret payload.
#
# WARNING: Do not print the secret in a production environment - this
# snippet is showing how to access the secret material.
payload = response.payload.data.decode("UTF-8")
print("Plaintext: {}".format(payload))
```

## IAM

### Custom Roles

If we know the exact permissions required, create a custom role with via `google_project_iam_custom_role` resource in terraform.

The caveat here is that custom bundle of permissions is set at a project wide level

### Roles with conditions

[Conditions overview doc](https://cloud.google.com/iam/docs/conditions-overview)

IAM policy can be set on different levels of access. From lowest to highest:

- resource
- project
- folder
- organization

Being a personal project we're mainly dealing with the first two - resource and project

Resource level policy is more restrictive - if we grant `roles/bigquery.admin` to only the one dataset, we are providing a guardrail for our service account to only deal with whichever dataset we want. Project level `admin` would be able to create, modify, and delete all datasets in that project.

Terraform has specific resource types for that, e.g. `google_storage_bucket_iam_member` or `google_bigquery_dataset_iam_member`, but gcloud CLI does not differentiate that way. Instead it relies on the `--condition` argument. If we only want `foo@proj.iam.gserviceaccount.com` to have `storage.admin` level on bucket `lake`, we would add the role normally, but attach a condition:

```bash
gcloud project add-iam-policy-binding PROJ_ID \
    --member='TYPE:EMAIL' \
    --role=ROLE \
    --condition=^:^resource.name==projects/_/buckets/BUCKET_NAME'
```

Can't get condition to be accepted.

## Test

1. start VM with the newly assigned service account attached
1. upload file to bucket
1. retrieve file from bucket
1. load file to bigquery dataset

```bash
# upload a file to GCS
BUCKET=
DATASET=
TABLE_ID=test_iam
echo "HELLO" > hello.txt && gsutil cp hello.txt gs://$BUCKET/hello.txt
# copy a parquet down
gsutil cp gs://$BUCKET/raw/pq/SR2020.parquet test.parquet
# load to a table in the bq dataset
bq load \
    --source_format=PARQUET \
    $DATASET.$TABLE_ID \
    test.parquet
```

- Needs `bigquery.jobs.create` at project level
- But due to the condition of dataset name, access to create tables in other datasets will still be denied
