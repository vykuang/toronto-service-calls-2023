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

# upload ward.geojson for bq load
resource "google_storage_bucket_object" "ward-geojson" {
  name = "code/city_wards.geojson"
  source = var.geojson_path
  bucket = google_storage_bucket.data-lake.name
}

# destination table for geojson
resource "google_bigquery_table" "ward-geojson" {
  deletion_protection = false
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  table_id = "city_wards_map"
#   depends_on = [google_bigquery_dataset.dataset]
}

# load geojson from bucket into table
resource "google_bigquery_job" "load_geojson" {
  job_id = "load_wards_geojson_${formatdate("YYYYMMDD_hhmmss", timestamp())}"
  load {
    source_uris = [
      "gs://${google_storage_bucket_object.ward-geojson.bucket}/${google_storage_bucket_object.ward-geojson.name}"
    ]

    destination_table {
    #   project_id = google_bigquery_table.ward-geojson.project
    #   dataset_id = google_bigquery_table.ward-geojson.dataset_id
      table_id =   google_bigquery_table.ward-geojson.id
    }
    write_disposition = "WRITE_TRUNCATE"
    autodetect = true
    source_format = "NEWLINE_DELIMITED_JSON"
    json_extension = "GEOJSON"
  }
  location = var.region
  depends_on = [
    google_storage_bucket_object.ward-geojson,
    google_bigquery_table.ward-geojson,
  ]
}

# load geojson as external table?
resource "google_bigquery_table" "load_geojson_ext" {
  deletion_protection = false
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  table_id = "city_wards_map_ext"
  external_data_configuration {
    autodetect = true
    source_format = "NEWLINE_DELIMITED_JSON"
    # json_extension = "GEOJSON"
    source_uris = [
      "gs://${google_storage_bucket_object.ward-geojson.bucket}/${google_storage_bucket_object.ward-geojson.name}"
    ]
  }
}
# define the blank canvas service account
resource "google_service_account" "service-agent" {
  account_id   = var.service_account_id
  display_name = var.service_account_name
  description  = "Service account supplying permissions for executor agent"
  project      = var.project_id
}

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

# still requires a few roles at project level
resource "google_project_iam_member" "service-agent-iam" {
  for_each = var.prefect_roles
  project = var.project_id
  role    = each.key
  member  = local.sa_member
}

# upload make-infra to bucket
resource "google_storage_bucket_object" "prefect-block" {
  name = "code/make_infra.py"
  source = "../flows/blocks/make_infra.py"
  bucket = google_storage_bucket.data-lake.name
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

# orchestration server
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

# prefect execution agent
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
    sudo pip3 install -U --no-cache-dir pip
    sudo pip3 install --no-cache-dir "prefect==2.8.4" prefect-dbt
    sudo chmod 666 /etc/environment
    sudo echo "export PATH="/home/$USER/.local/bin:$PATH"" >> /etc/environment
    sudo echo "export TF_VAR_project_id=${var.project_id}" >> /etc/environment
    sudo echo "export TF_VAR_region=${var.region}" >> /etc/environment
    sudo echo "export TF_VAR_zone=${var.zone}" >> /etc/environment
    sudo echo "export TF_VAR_data_lake_bucket=${var.data_lake_bucket}" >> /etc/environment
    sudo echo "export TF_VAR_bq_dataset=${var.bq_dataset}" >> /etc/environment
    source /etc/environment
    sudo chmod 444 /etc/environment
    prefect config set PREFECT_API_URL="http://${google_compute_instance.server.network_interface.0.access_config.0.nat_ip}:4200/api"
    # make_infra
    mkdir /code && cd /code
    gsutil cp ${google_storage_bucket.data-lake.url}/code/make_infra.py make_infra.py
    python3 make_infra.py
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
