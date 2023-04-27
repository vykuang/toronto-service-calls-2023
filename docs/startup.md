# Start-up scripts for VMs

Primer on the startup scripts included in terraform `main.tf` for the compute instances

## prefect server

```sh
    # 0. only run on initial launch, not subsequent startups
if [[ -f /etc/startup_was_launched ]]; then exit 0; fi
    # 1. proactively set it so gcloud asks fewer questions
    gcloud config set compute/zone ${var.zone}
    # 2. Normal startup
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    # 3. install our packages, which for server is simply python and prefect
    sudo apt install python3-pip -y
    pip3 install -U pip "prefect==2.8.4"
    # 4. edit the system wide env file; only supports simple assignment
    sudo chmod 666 /etc/environment
    # 5. text editing to retrieve instance's external IP
    sudo echo "EXTERNAL_IP=$(gcloud compute instances describe server --zone ${var.zone}| grep natIP | cut -d: -f 2 | tr -d ' ' | tail -n 1)" >> /etc/environment
    source /etc/environment
    sudo chmod 444 /etc/environment
    # 6. signpost
    sudo touch /etc/startup_was_launched
    # 7. start server
    prefect config set PREFECT_UI_API_URL=http://$EXTERNAL_IP:4200/api
    # 8. 0.0.0.0 accepts all incoming IPs
    prefect server start --host 0.0.0.0
```

## prefect agent

```sh
if [[ -f /etc/startup_was_launched ]]; then exit 0; fi
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    # 1. install docker, per offical docs
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
    # 2. install packages
    sudo apt install python3-pip -y
    sudo pip3 install -U --no-cache-dir pip
    sudo pip3 install --no-cache-dir "prefect==2.8.4"
    # 3. set environment for agent
    sudo chmod 666 /etc/environment
    sudo echo "PREFECT_API_URL=http://${google_compute_instance.server.network_interface.0.access_config.0.nat_ip}:4200/api" >> /etc/environment
    sudo echo "TF_VAR_project_id=${var.project_id}" >> /etc/environment
    sudo echo "TF_VAR_region=${var.region}" >> /etc/environment
    sudo echo "TF_VAR_zone=${var.zone}" >> /etc/environment
    sudo echo "TF_VAR_data_lake_bucket=${var.data_lake_bucket}" >> /etc/environment
    sudo echo "TF_VAR_bq_dataset=${var.bq_dataset}" >> /etc/environment
    set -o allexport
    # 4. "." more widely applicable than source
    . /etc/environment
    set +o allexport
    sudo chmod 444 /etc/environment
    prefect config set PREFECT_API_URL=$PREFECT_API_URL
    # 5. create the infra and storage blocks
    mkdir code && cd code
    gsutil cp ${google_storage_bucket.data-lake.url}/code/make_*.py .
    python3 make_infra.py
    python3 make_gcs_sb.py
    # 6. create flag to indicate instance has been launched before
    sudo touch /etc/startup_was_launched
    # 7. start agent
    prefect agent start -q service-calls
```
