#!/bin/bash
set -e
echo "--- Installing Docker and common tools ---"
sudo apt update -y
sudo apt install -y net-tools ca-certificates curl git ufw
if ! [ -x "$(command -v docker)" ]; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    sudo usermod -aG docker $USER || true
fi
echo "--- Docker setup complete ---"
