#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "--- Starting Machine Setup ---"

# 1. Update package index
sudo apt update -y

# 2. Install Basic Utilities (git, nano, python, net-tools)
echo "--- Installing Basic Tools ---"
sudo apt install -y git nano python3 python3-pip net-tools build-essential

# 3. Setup SSH Public Keys
echo "--- Configuring SSH Keys ---"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
curl -sL https://github.com/ashish-koshy.keys >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "SSH keys imported successfully."

# 4. Install Docker Engine
echo "--- Installing Docker ---"
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Configure Docker Permissions
echo "--- Configuring Docker permissions ---"
sudo groupadd -f docker
sudo usermod -aG docker $USER

echo "--- Setup Complete! ---"
echo "NOTE: Run 'newgrp docker' or log out/in to use Docker without sudo."
