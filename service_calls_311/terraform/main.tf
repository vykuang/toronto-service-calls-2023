terraform {
  required_version = ">= 1.0"
  # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  backend "gcs" {}
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  // credentials = file(var.credentials)  # Use this if you do not want to set env-var GOOGLE_APPLICATION_CREDENTIALS
}

### REMOVED google_project; create manually via CLI or console
resource "google_project_service" "services" {
  for_each                   = var.gcp_service_list
  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = false
}
resource "google_storage_bucket" "data-lake" {
  name                        = var.data_lake_bucket
  location                    = var.region
  force_destroy               = true
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning {
    enabled = false
  }
}
resource "google_bigquery_dataset" "dataset" {
  dataset_id  = var.bq_dataset
  description = "Contains all tables for the 311 service call project"
  location    = var.region
}


# define the blank canvas service account
resource "google_service_account" "service-agent" {
  account_id   = var.service_account_id
  display_name = var.service_account_name
  description  = "Service account supplying permissions for executor agent"
  project      = var.project_id
}

# resource "google_project_iam_custom_role" "custom-service-role" {
#   role_id = "customPrefectAgent"
#   title   = "Custom Prefect Agent"
#   # agent_permissions defined in variables.tf as set of strings
#   permissions = [for allow in var.agent_permissions : allow]
#   description = "Custom role for agent to access cloud storage and create bigquery tables"
# }

# # assign the role to the service account
# resource "google_project_iam_member" "service-agent-iam" {
#   project = var.project
#   # assigning predefined roles
#   # for_each = var.prefect_roles
#   # role = each.key
#   # assigning the custom role
#   role   = google_project_iam_custom_role.custom-prefect-role.id
#   member = "serviceAccount:${google_service_account.service-agent.email}"
# }
locals {
  sa_member = "serviceAccount:${google_service_account.service-agent.email}"
}
# assign the bucket role to our service account
resource "google_storage_bucket_iam_member" "service-agent-iam" {
  bucket = google_storage_bucket.data-lake.name
  role   = "roles/storage.admin"
  member = local.sa_member
}
# dataset admin
resource "google_bigquery_dataset_iam_member" "service-agent-iam" {
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  role       = "roles/bigquery.admin"
  member     = local.sa_member
}

# still requires bigquery.jobUser at project level
resource "google_project_iam_member" "service-agent-iam" {
  for_each = var.prefect_roles
  project = var.project_id
  role    = each.key
  member  = local.sa_member
}

# upload agent-startup.sh to bucket
resource "google_storage_bucket_object" "prefect-block" {
  name = "code/make_infra.py"
  source = "../flows/blocks/make_infra.py"
  bucket = google_storage_bucket.data-lake.name
}
# secret to store PREFECT_API_KEY
resource "google_secret_manager_secret" "prefect" {
  secret_id = "prefect-api-key"
  replication {
    automatic = true
  }
  depends_on = [google_project_service.services["secretmanager.googleapis.com"]]
}
# secret to store
resource "google_secret_manager_secret" "test" {
  secret_id = "prefect-test-key"
  replication {
    automatic = true
  }
  depends_on = [google_project_service.services["secretmanager.googleapis.com"]]
}
# test secret
resource "google_secret_manager_secret_version" "prefect-key" {
  secret = google_secret_manager_secret.test.id
  secret_data = var.prefect_api_key
}
data "google_compute_image" "default" {
  family  = "ubuntu-2004-lts"
  project = "ubuntu-os-cloud"
}
data "google_compute_image" "prefect" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# Wait for the new configuration to propagate
# (might be redundant)
resource "time_sleep" "wait_service_enable" {
  create_duration = "10s"

  depends_on = [google_project_service.services]
}

# test?
resource "google_compute_instance" "default" {
  name         = "test"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      size  = 10
      type  = "pd-standard"
      image = data.google_compute_image.default.self_link
    }

  }
  network_interface {
    network = "default"
    access_config {
      network_tier = "STANDARD"

    }
  }
  service_account {
    email  = google_service_account.service-agent.email
    scopes = ["cloud-platform"]
  }
  depends_on = [time_sleep.wait_service_enable]
}

# test?
resource "google_compute_instance" "server" {
  name         = "server"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      size  = 10
      type  = "pd-standard"
      image = data.google_compute_image.prefect.self_link
    }

  }
  network_interface {
    network = "default"
    access_config {
      network_tier = "STANDARD"

    }
  }
  metadata_startup_script = <<SCRIPT
    if [[ -f /etc/startup_was_launched ]]; then exit 0; fi
    gcloud config set compute/zone ${var.zone}
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    sudo apt install python3-pip -y
    pip3 install -U pip "prefect==2.8.4"
    sudo chmod 666 /etc/environment
    sudo echo "export PATH="/home/$USER/.local/bin:$PATH"" >> /etc/environment
    sudo echo "export EXTERNAL_IP=$(gcloud compute instances describe ${google_compute_instance.server.name} | grep natIP | cut -d: -f 2 | tr -d ' '
    source /etc/environment
    sudo chmod 444 /etc/environment
    touch /etc/startup_was_launched
    prefect config set PREFECT_UI_API_URL=http://$EXTERNAL_IP:4200/api
    prefect server start --host 0.0.0.0
    SCRIPT
  service_account {
    email  = google_service_account.service-agent.email
    scopes = ["cloud-platform"]
  }
  depends_on = [time_sleep.wait_service_enable]
}

# prefect agent?
resource "google_compute_instance" "agent" {
  name         = "agent"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      size  = 10
      type  = "pd-standard"
      image = data.google_compute_image.prefect.self_link
    }

  }
  metadata = {
    # startup-script-url = "gs://service-data-lake/code/agent-startup.sh"

  }
  metadata_startup_script = <<SCRIPT
    if [[ -f /etc/startup_was_launched ]]; then exit 0; fi
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    sudo apt remove docker docker-engine docker.io containerd runc -y
    sudo apt install \
        ca-certificates \
        curl \
        gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    sudo usermod -aG docker $USER
    newgrp docker
    sudo apt install python3-pip -y
    pip3 install -U pip "prefect==2.8.4" prefect-dbt
    sudo chmod 666 /etc/environment
    sudo echo "export PATH="/home/$USER/.local/bin:$PATH"" >> /etc/environment
    sudo echo "export TF_VAR_project_id=${var.project_id}" >> /etc/environment
    sudo echo "export TF_VAR_region=${var.region}" >> /etc/environment
    sudo echo "export TF_VAR_zone=${var.zone}" >> /etc/environment
    sudo echo "export TF_VAR_data_lake_bucket=${var.data_lake_bucket}" >> /etc/environment
    sudo echo "export TF_VAR_bq_dataset=${var.bq_dataset}" >> /etc/environment
    source /etc/environment
    sudo chmod 444 /etc/environment
    prefect config set PREFECT_API_URL="https://${google_compute_instance.server.network_interface.0.access_config.0.nat_ip}:4200/api"
    # make_infra
    mkdir /code && cd /code
    gsutil cp ${google_storage_bucket.data-lake.url}/code/make_infra.py make_infra.py
    python make_infra.py
    # create flag to indicate instance has been launched before
    touch /etc/startup_was_launched
    prefect agent start -q service-calls
    SCRIPT
  network_interface {
    network = "default"
    access_config {
      network_tier = "STANDARD"

    }
  }
  service_account {
    email  = google_service_account.service-agent.email
    scopes = ["cloud-platform"]
  }
  depends_on = [
    time_sleep.wait_service_enable,
    google_compute_instance.server,
    google_storage_bucket_object.prefect-block
  ]
}
# resource "google_storage_bucket" "dp-staging" {
#     name = var.dp_staging
#     location = var.region
#     storage_class = var.storage_class
#     uniform_bucket_level_access = true
#     public_access_prevention = "enforced"
# }
# resource "google_storage_bucket" "dp-temp" {
#     name = var.dp_temp
#     location = var.region
#     storage_class = var.storage_class
#     uniform_bucket_level_access = true
#     public_access_prevention = "enforced"
# }
# resource "google_dataproc_cluster" "service-call-cluster" {
#     name = var.dp_cluster
#     region = var.region
#     graceful_decommission_timeout = "120s"
#     cluster_config {
#         staging_bucket = var.dp_staging
#         temp_bucket = var.dp_temp

#         master_config {
#             num_instances = 1
#             machine_type  = "e2-medium"
#             disk_config {
#                 boot_disk_type    = "pd-ssd"
#                 boot_disk_size_gb = 10
#             }
#         }
#         worker_config {
#             num_instances    = 2
#             machine_type     = "e2-medium"
#             min_cpu_platform = "Intel Skylake"
#             disk_config {
#                 boot_disk_size_gb = 30
#                 num_local_ssds    = 1
#             }
#         }
#         preemptible_worker_config {
#             num_instances = 0
#         }
#     }
# }
