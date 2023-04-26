#!/usr/bin/env bash
# coding: utf-8

# only run if initial instance start
if [[ -f /etc/startup_was_launched ]]; then exit 0; fi
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
# install docker
# remove existing
sudo apt remove docker docker-engine docker.io containerd runc -y
# allow apt to use repo over https
sudo apt install \
    ca-certificates \
    curl \
    gnupg
# add docker gpg key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
# setup docker repo
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
# install from repo
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
# allow non-root usage
# sudo groupadd docker # ubuntu automatically creates docker group
sudo usermod -aG docker $USER
newgrp docker
# install prefect
sudo apt install python3-pip -y
pip3 install -U pip "prefect==2.8.4"
echo "export PATH="/home/$USER/.local/bin:${PATH}"" > ~/.bashrc
source ~/.bashrc
# make_infra

# create flag to indicate instance has been launched before
touch /etc/startup_was_launched
