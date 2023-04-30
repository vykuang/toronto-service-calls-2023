# GCE instance startup scripts

Brief primer on the `metadata_startup_script` block in `terraform/main.tf`

## server

```sh
# only run on initial startup, not on reset
if [[ ! -f /etc/startup_was_launched ]]; then
    gcloud config set compute/zone ${var.zone}
    # prepares env
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    # install and upgrade pip and prefect
    sudo apt install python3-pip -y
    pip3 install -U pip "prefect==2.8.4"
    # allow edit; this is a sys wide version of .bashrc, but only simple assignments allowed
    sudo chmod 666 /etc/environment
    # retrieves host instance's external IP
    sudo echo "EXTERNAL_IP=$(gcloud compute instances describe server --zone ${var.zone}| grep natIP | cut -d: -f 2 | tr -d ' ' | tail -n 1)" >> /etc/environment
    # . is more widely applicable than source
    . /etc/environment
    # return to read only
    sudo chmod 444 /etc/environment
    # initial launch flag
    sudo touch /etc/startup_was_launched
    prefect config set PREFECT_UI_API_URL=http://$EXTERNAL_IP:4200/api
fi
# run every startup
prefect server start --host 0.0.0.0
```

## agent

```sh
# initial launch only
if [[ ! -f /etc/startup_was_launched ]]; then
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    # install docker, from https://docs.docker.com/engine/install/ubuntu/
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
```

```sh
    # continued
    # pip, prefect
    sudo apt install python3-pip -y
    sudo pip3 install -U --no-cache-dir pip
    sudo pip3 install --no-cache-dir "prefect==2.8.4"
    # edit env
    sudo chmod 666 /etc/environment
    # sets environment var; this allows script to be edited at terraform apply
    # makes it more portable
    sudo echo "PREFECT_API_URL=http://${google_compute_instance.server.network_interface.0.access_config.0.nat_ip}:4200/api" >> /etc/environment
    sudo echo "TF_VAR_project_id=${var.project_id}" >> /etc/environment
    sudo echo "TF_VAR_region=${var.region}" >> /etc/environment
    sudo echo "TF_VAR_zone=${var.zone}" >> /etc/environment
    sudo echo "TF_VAR_data_lake_bucket=${var.data_lake_bucket}" >> /etc/environment
    sudo echo "TF_VAR_bq_dataset=${var.bq_dataset}" >> /etc/environment
    set -o allexport
    . /etc/environment
    set +o allexport
    sudo chmod 444 /etc/environment
    # connect to prefect server via external IP
    prefect config set PREFECT_API_URL=$PREFECT_API_URL
    # creates prefect blocks after connecting to server
    mkdir code && cd code
    gsutil cp ${google_storage_bucket.data-lake.url}/code/make_*.py .
    python3 make_infra.py
    python3 make_gcs_sb.py
    # create flag to indicate instance has been launched before
    sudo touch /etc/startup_was_launched
fi
# always run on startup
prefect agent start -q service-calls
```
