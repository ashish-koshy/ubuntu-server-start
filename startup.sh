#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "--- Starting Machine Setup ---"

# 1. Update package index and Enable IP Forwarding
echo "--- Updating System & Enabling IP Forwarding ---"
sudo apt update -y
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 2. Install Basic Utilities & Docker
echo "--- Installing Tools & Docker Engine ---"
sudo apt install -y git curl ufw ca-certificates build-essential

# Docker Installation logic
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
sudo usermod -aG docker $USER || true

# 3. Setup Project Directory
mkdir -p ~/wireguard-stack
cd ~/wireguard-stack

# 4. WireGuard + Caddy Setup (Interactive with Defaults)
echo ""
read -p "Do you want to setup WireGuard (wg-easy) with Caddy? (y/n): " install_wg
if [[ "$install_wg" =~ ^[Yy]$ ]]; then    
    # Domain Input with Default
    read -p "Enter your VPN Domain [default: vpn.ackaboo.com]: " WG_DOMAIN
    WG_DOMAIN=${WG_DOMAIN:-vpn.ackaboo.com}

    # Email Input with Default
    read -p "Enter your Email [default: reply@webmail.ackaboo.com]: " WG_EMAIL
    WG_EMAIL=${WG_EMAIL:-reply@webmail.ackaboo.com}

    # Password Input
    read -s -p "Enter Admin Password: " WG_PASSWORD
    echo ""

    echo "--- Generating Secure Password Hash ---"
    # Generate hash once and store in variable
    WGPW_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:latest node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('$WG_PASSWORD', 10));")
    
    # Create Caddyfile
    cat <<EOF > Caddyfile
{
    email $WG_
