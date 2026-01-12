#!/bin/bash

set -e

echo "--- Starting Machine Setup ---"

# 1. System Updates & IP Forwarding
echo "--- Updating System & Enabling IP Forwarding ---"
sudo apt update -y
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 2. Basic Tools & Docker Engine Installation
echo "--- Installing Basic Tools & Docker ---"
sudo apt install -y git curl ufw ca-certificates build-essential

# (Docker Install Logic)
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
sudo usermod -aG docker $USER

# 3. Project Directory Setup
mkdir -p ~/wireguard-stack
cd ~/wireguard-stack

# 4. WireGuard + Caddy Setup (Interactive)
echo ""
read -p "Do you want to setup WireGuard (wg-easy) with Caddy Reverse Proxy? (y/n): " install_wg
if [[ "$install_wg" =~ ^[Yy]$ ]]; then
    read -p "Enter your VPN Domain (e.g., vpn.example.com): " WG_DOMAIN
    read -p "Enter your Email (for SSL certs): " WG_EMAIL
    read -s -p "Enter Admin Password: " WG_PASSWORD
    echo ""

    echo "--- Generating Secure Password Hash ---"
    WGPW_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:latest node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('$WG_PASSWORD', 10));" | tr -d '\r\n')

    # Create Caddyfile
    cat <<EOF > Caddyfile
{
    email $WG_EMAIL
}

$WG_DOMAIN {
    reverse_proxy wg-easy:51821
}
EOF

    # Create compose.yml
    cat <<EOF > compose.yml
services:
  caddy:
    image: caddy:2.7-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - vpn_net

  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    restart: unless-stopped
    environment:
      - WG_HOST=$WG_DOMAIN
      - PASSWORD_HASH=$WGPW_HASH
      - WG_PORT=51820
    volumes:
      - ./wg_etc:/etc/wireguard
    ports:
      - "51820:51820/udp"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    networks:
      - vpn_net

networks:
  vpn_net:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
EOF

    # UFW Rules for WG + Caddy
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 443/udp
    sudo ufw allow 51820/udp
    
    echo "--- Starting WireGuard and Caddy ---"
    sudo docker compose up -d
fi

# 5. Cloudflared Tunnel Setup (Interactive)
echo ""
read -p "Do you want to install Cloudflared? (y/n): " install_cf
if [[ "$install_cf" =~ ^[Yy]$ ]]; then
    read -p "Enter your Cloudflare Tunnel Token: " CF_TOKEN
    sudo docker rm -f cloudflared || true
    sudo docker run -d \
      --name cloudflared \
      --network host \
      --restart always \
      cloudflare/cloudflared:latest \
      tunnel --no-autoupdate run --token "$CF_TOKEN"
fi

sudo ufw allow ssh
sudo ufw --force enable

echo "--- Setup Complete! ---"
