#!/bin/bash
set -eu -o pipefail

# Install necessary dependencies
sudo apt-get update
sudo apt-get -y -qq install ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin git unzip auditd

# Get HashiCups config
git clone https://github.com/hashicorp-demoapp/hashicups-setups
cd hashicups-setups/docker-compose-deployment
git checkout server

HASHICUPS_VERSION="v1.1.0"
sed -i 's/HashiCups/HashiCups - ${HASHICUPS_VERSION}/g' docker-compose.yaml

# Use `compose create` to fetch container data without starting the container
sudo docker compose create

# Configure HashiCups to start on boot using systemd
sudo cp /tmp/hashicups.service /etc/systemd/system/hashicups.service
sudo systemctl daemon-reload
sudo systemctl enable hashicups
