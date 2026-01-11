#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "--- Starting Machine Setup ---"

# 1. Update package index and Enable IP Forwarding
echo "--- Updating System & Enabling IP Forwarding ---"
sudo apt update -y
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 2. Install Basic Utilities
echo "--- Installing Basic Tools (git, nano, python, net-tools) ---"
sudo apt install -y git nano python3 python3-pip net-tools build-essential ufw ca-certificates curl

# 3. Setup SSH Public Keys (Idempotent)
echo "--- Configuring SSH Keys ---"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys

# Fetch keys from GitHub and only add if they don't already exist
curl -sL https://github.com/ashish-koshy.keys | while read -r key; do
    if ! grep -qF "$key" ~/.ssh/authorized_keys; then
        echo "$key" >> ~/.ssh/authorized_keys
        echo "Added new key from GitHub."
    fi
done
chmod 600 ~/.ssh/authorized_keys

# 4. Configure Firewall (UFW)
echo "--- Configuring Firewall ---"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 51000/udp   # WireGuard VPN Port
sudo ufw --force enable

# 5. Install Docker Engine
echo "--- Installing Docker Engine ---"
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

# 6. Configure Docker Permissions
echo "--- Configuring Docker permissions ---"
sudo groupadd -f docker
sudo usermod -aG docker $USER

# 7. Optional WireGuard Setup (wg-easy)
echo ""
read -p "Do you want to setup WireGuard (wg-easy)? (y/n): " install_wg
if [[ "$install_wg" =~ ^[Yy]$ ]]; then
    # Detect Private IP for Tunnel Routing
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    
    read -p "Enter your VPN Domain (Grey Cloud, e.g., vpn.abc.com): " WG_DOMAIN
    read -p "Enter Admin Username [admin]: " WG_USER
    WG_USER=${WG_USER:-admin}
    read -s -p "Enter Admin Password: " WG_PASSWORD
    echo ""

    echo "--- Starting wg-easy on Private IP: $PRIVATE_IP ---"
    sudo docker run -d \
      --name wg-easy \
      --env INIT_ENABLED=true \
      --env INIT_USERNAME="$WG_USER" \
      --env INIT_PASSWORD="$WG_PASSWORD" \
      --env WG_HOST="$WG_DOMAIN" \
      --env WG_PORT=51000 \
      --env INSECURE=true \
      -v ~/.wg-easy:/etc/wireguard \
      -v /lib/modules:/lib/modules:ro \
      -p 51000:51000/udp \
      -p ${PRIVATE_IP}:51821:51821/tcp \
      --cap-add=NET_ADMIN \
      --cap-add=SYS_MODULE \
      --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
      --sysctl="net.ipv4.ip_forward=1" \
      --restart always \
      ghcr.io/wg-easy/wg-easy
fi

# 8. Optional Cloudflared Tunnel Setup
echo ""
read -p "Do you want to install a NEW Cloudflare Tunnel container? (y/n): " install_cf
if [[ "$install_cf" =~ ^[Yy]$ ]]; then
    read -p "Enter your Cloudflare Tunnel Token: " CF_TOKEN
    sudo docker run -d \
      --name cloudflared \
      --restart always \
      cloudflare/cloudflared:latest \
      tunnel --no-autoupdate run --token "$CF_TOKEN"
    echo "--- Cloudflared container started ---"
else
    echo "--- Skipping Tunnel installation (assuming existing setup) ---"
fi

echo ""
echo "--- Setup Complete! ---"
echo "VERIFICATION STEPS:"
echo "1. If using a Tunnel, point the Service URL to: http://${PRIVATE_IP:-[PRIVATE_IP]}:51821"
echo "2. Run 'newgrp docker' to use docker without sudo in this session."
echo "3. Status check: docker ps"
