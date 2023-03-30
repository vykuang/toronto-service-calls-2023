# Terraform

At its simplest, simply specify a `main.tf` with a `resource` block:

```tf
# main.tf
resource "google_storage_bucket" "data-lake" {
    name = data_lake_bucket_name
    location = gcp_region
    force_destroy = true
    storage_class = some_storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
}
```

then run these commands

```bash
terraform init
terraform apply
```

to have terraform build the specified bucket.

## Required permissions

To allow terraform effect these infra changes, the account running `apply` will need these roles/permissions:

- roles/resourcemanager.projectIamAdmin - assign roles to service accounts
- roles/iam.roleAdmin - create custom roles
- bigquery.datasets.create
- bigquery.datasets.delete
- storage.buckets.create
- storage.buckets.delete

If running as `Owner`, should be fine

## Backend

[Offical docs](https://developer.hashicorp.com/terraform/language/settings/backends/configuration#partial-configuration)

This is the storage for the `.tfstate` state files, where terraform keeps record of the state of cloud infrastructure. Specify in top level `terraform` block inside `main.tf`:

```tf
# main.tf
terraform {
  required_version = ">= 1.0"
  # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  backend "gcs" {
    bucket = "service-call-tf-states"
    prefix = "terraform/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
  }
}
```

Most likely we'll want some remote cloud storage. Paradox is that the backend bucket needs to be made beforehand for terraform to use it. So we need to manually make a bucket before letting terraform build our cloud infra? It's not unreasonable, but appears a little counter-intuitive.
`terraform` block also does not allow input variables (from `variables.tf`) to be used, but allows the `backend` block to be configured via these methods when running `terraform init`, *if the backend block exists, and is empty*:

1. CLI argument: `-backend-config="KEY=VALUE"`; repeat for each K/V pair
1. file: `-backend-config=path/to/config.gcs.tfbackend`
    - file lists all the `KEY = VALUE` pairs in top level

To parametrize the backend bucket, CLI seems more approachable.

```bash
# set name for tfstate bucket
TFSTATE_BUCKET=some_gcs_bucket`
# make bucket;
# -l: region; -b on: uniform access; --pap: public access prevention
gsutil mb \
    -l us-west1 \
    -b on \
    --pap enforced \
    gs://$TFSTATE_BUCKET
# may have to add -migrate-state option
terraform init \
    -backend-config="bucket=$TFSTATE_BUCKET" \
    -backend-config="prefix=terraform/state"
```

If successful, in addition to terminal log, a `.terraform/` folder and `.terraform.lock.hcl` file will appear
## Provider

Specify our project ID, default region, and if not already on GCE, path to cloud credential

```tf
provider "google" {
    project = var.project
    region = var.region
    # Use this if you do not want to set env var GOOGLE_APPLICATION_CREDENTIALS
    # credentials in variables.tf has path to file
    // credentials = file(var.credentials)
}
```

## Resources

[gcp provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

- gcs bucket as data lake and storage for dataproc cluster
- bigquery dataset
- dataproc cluster

```tf
resource "google_storage_bucket" "data-lake" {
    name = var.data_lake_bucket
    location = var.region
    force_destroy = true
    storage_class = var.storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
}
resource "google_bigquery_dataset" "dataset" {
    dataset_id = var.bq_dataset
    description = "Contains all models for the 311 service call project"
    location = var.region
}
resource "google_storage_bucket" "dp-staging" {
    name = var.dp_staging
    location = var.region
    storage_class = var.storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
}
resource "google_storage_bucket" "dp-temp" {
    name = var.dp_temp
    location = var.region
    storage_class = var.storage_class
    uniform_bucket_level_access = true
    public_access_prevention = "enforced"
}
resource "google_dataproc_cluster" "service-call-cluster" {
    name = var.dp_cluster
    region = var.region
    description = "Runs spark jobs for the service call project"
    cluster_config {
        staging_bucket = var.dp_staging
        temp_bucket = var.dp_temp
    }
}
```

### Authentication

There are several components:

- google_iam_policy - this defines the roles that can be applied to service accounts
- google_service_account - creates the service account
- google_service_account_iam_policy - assigns the roles to the account
    - there is also ...account_iam_*binding* and account_iam_*member* which update the policies as opposed to a blanket overwrite
    - the above do *not* assign roles to service accounts; instead they treat the service accounts as resources, and allow other members, e.g. users or other service accounts to perform tasks as that service account
    - so technically we could create a dummy SA, assign it permissions A, B, and C, then assign all the members to the dummy SA so that they could execute their tasks *as dummy SA*, which again, has the required permissions
- more straightforwardly let's use `google_project_iam_policy`

### service account

[terraform docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account#argument-reference)

```
resource "google_service_account" "prefect-agent" {
    account_id = var.credentials_id
    display_name = var.credentials_display
    description = "Service account supplying permissions for prefect agent"
    project = var.project
}
```

This also exports these attributes, accessible by `<resource_type>.<resource_name>.attribute`:

- id
- email
- name - fully qualified name, to be used in `google_service_account_iam_policy` when specifying which accounts will be assigned the roles
- unique_id
- member

### IAM policy and roles

[docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/iam_policy)

[list of complete roles. MUST START WITH `Roles/`](https://cloud.google.com/compute/docs/access/iam)

As opposed to service account, this is a `data source`, which defines a document for `google_service_account_iam_policy` to apply to `google_service_account`

Takes `binding`, which is a block containing `role` and `member`; multiple roles will require multiple `binding` blocks and the same `member`:

```
data "google_iam_policy" "prefect-role" {
    binding {
        role = "roles/bigquery.dataEditor"
        members = [
            "serviceAccount:${google_service_account.prefect-agent.email}"
        ]
    }
    binding {
        role = "bigquery.jobUser"
        members = [
            "serviceAccount:${google_service_account.prefect-agent.email}"
        ]
    }
}
```

Note the use of interpolation via `${...}` so that we can make use of `google_service_account`'s exported attribute

### IAM Policy assignment

NOTE: this assigns `service_acount_id` as a resource to all `member/s`; it does not assign permission roles. In fact most likely the only role we'd use here is `roles/iam.serviceAccountUser` related. `roles/iam.serviceAccountAdmin` is required to manage access to SAs

[docs here](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account_iam#google_service_account_iam_policy)

```
resource "google_service_account_iam_policy" "prefect-agent-iam" {
    service_account_id = google_service_account.prefect-agent.name
    policy_data = data.google_iam_policy.prefect-role.policy_data
}
```

Make use of the exported attributes of the resource/data source in defining this resource block

### `google_project_iam`

The service_account variant did not work, need to use `project`. On default service account from my compute engine, ran into this error:

```bash
Error setting IAM policy for project "de-zoom-83": googleapi: Error 403: Policy update access denied., forbidden
```

From [this post here](https://stackoverflow.com/a/65661736) it seems that whichever account running this terraform command needs to have the `resourcemanager.projects.setIamPolicy` permission

Predefined roles with that permission:

- roles/iam.securityAdmin
- roles/resourcemanager.projectIamAdmin

Try adding that to my compute `admin` service account...

The differences between the three are:

- `policy` - sets all roles for all members in the project; defines a complete policy for the project
- `binding` - defines all members of the role
    - if we're binding role A to members F, H, and G had role A before, then `binding` would grant role A only to F and H, and revoke it from G
- `member` - updates member list for that role

### service account background

Service accounts are simultaneously resources that other principals can be granted access to, as well as principals that can be granted access to other resources.

- in the former, a service account could be a default GCE service account with access to GCE resources, and we may want to grant those access to another account, e.g. user account
- in the latter, we may have created a service account for a specific application, and we want to grant access from a default bigquery account to that newly created SA

What we want to accomplish here is distinctly different, because we want to attach *roles* to our service account. These roles provide access to various cloud resources. The collection of *roles* make up the **IAM policy**, aka allow policy.

What we're interested in is [granting roles to principals](https://cloud.google.com/iam/docs/granting-changing-revoking-access), which falls under managing access to projects, folders, and orgs. `Cloud Resource Manager API` must enabled in console:

```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member=PRINCIPAL_TYPE:PRINCIPAL_ID\
    --role=roles/iam.securityAdmin \
    --condition=CONDITION
```

- PRINCIPAL_TYPE: is probably `serviceAccount`
- PRINCIPAL_ID: the email associated with the account, or its unique numeric ID
- roles: must start with roles/...
- conditions: optional; must be fulfilled for the specified role to be granted. Not applicable to basic roles, e.g. roles/owner, editor, viewer.
    - date/time
    - resource attributes, e.g. prefix of account ID must match some pattern
- `remove-iam-policy-binding` to revoke the role
- `set-iam-policy` overwrites instead of append, and requires passing a file that includes the complete list of policies for that project

After creating the SA and binding the necessary roles, create the key file with

```bash
gcloud iam service-accounts keys create key.json \
    --iam-account=my-iam-account@my-project.iam.gserviceaccount.com \
    --key-file-type=json
```

The terraform resource is `google_project_iam_binding` or `_member`; binding defines which members for this role, and member simply adds users to that role

### `for_each`

[offical docs](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)

When applying multiple roles to our SA, the normal syntax requires one resource block per role, e.g.

```tf
resource "google_project_iam_member" "prefect-agent-iam" {
    project = var.project
    role = "roles/A"
    member = "serviceAccount:${google_service_account.prefect-agent.email}"
}
resource "google_project_iam_member" "prefect-agent-iam" {
    project = var.project
    role = "roles/B"
    member = "serviceAccount:${google_service_account.prefect-agent.email}"
}
```

But we can declare a whole array in `variables.tf`, and then use `for_each` in `main.tf`:

```tf
# variables.tf
variable "prefect_roles" {
    description = "list of roles assigned to the executor service account"
    type = set(string)
    default = [
        "roles/bigquery.dataEditor",
        "roles/bigquery.jobUser",
        "roles/storage.admin"
    ]
}

# main.tf
resource "google_project_iam_member" "prefect-agent-iam" {
    project = var.project
    for_each = var.prefect_roles
    role = each.key
    member = "serviceAccount:${google_service_account.prefect-agent.email}"
}
```

Terraform will expand `resource "google_project_iam_member"` as it iterates through our list. Use `each.key` to correspond to the set member, and `each.value` if it's a map instead of a list

### Custom roles

In the case where we know exactly what `permissions` are required, e.g. `storage.buckets.list`, we can create a custom role to remove excessive permissions from being granted to our service account.

Requires `roles/iam.roleAdmin` to manage roles for a project

[Terraform resource:](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_iam_custom_role)

```tf
resource "google_project_iam_custom_role" "custom-prefect-role" {
  role_id     = "customPrefectAgent"    # required
  title       = "Custom Prefect Agent"  # required
  permissions = ["storage.bucket.get", "storage.bucket.list"] # required
  description = "Custom role for agent to access cloud storage and create bigquery tables"
}
```

[gcloud equiv:](https://cloud.google.com/sdk/gcloud/reference/iam/roles/create)

```bash
gcloud iam roles create ProjectUpdater \
    --title=ProjectUpdater \
    --permissions=resourcemanager.projects.get,resourcemanager.projects.update \
    --project=myproject \
    --description="Have access to get and update the project"
```

Alternatively, instead of passing `permissions`, pass `file` and point to path of JSON/YAML specifying the permissions

## Modules

Containers for multiple resources used together; consists of a collection of `.tf` or `.tf.json` kept together in a directory. Every terraform config has at least one module, the *root module*, containing `main.tf`

Modules can also be imported from the terraform registry, made by official providers, e.g. google. Think of it like a python library that provides useful functions without you coding it from scratch

## Best practice

- `terraform fmt` to autoformat the `.tf` files
