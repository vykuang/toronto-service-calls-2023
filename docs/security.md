# secrets manager

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
