#!/bin/bash

set -e

echo "--- Starting Machine Setup with Caddy & Docker Compose ---"

# 1. System Updates & IP Forwarding
sudo apt update -y
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 2. Install Tools & Docker
sudo apt install -y git curl ufw
# (Assuming Docker is installed via the previous script steps or already present)

# 3. Create Project Directory
mkdir -p ~/wireguard-stack
cd ~/wireguard-stack

# 4. Get User Inputs
read -p "Enter your VPN Domain (e.g., vpn.example.com): " WG_DOMAIN
read -p "Enter your Email (for Let's Encrypt): " WG_EMAIL
read -s -p "Enter WireGuard Web UI Admin Password: " WG_PASSWORD
echo ""

# 5. Generate Password Hash
echo "--- Generating Secure Password Hash ---"
WGPW_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:latest node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('$WG_PASSWORD', 10));" | tr -d '\r\n')

# 6. Create Caddyfile
cat <<EOF > Caddyfile
{
    email $WG_EMAIL
}

$WG_DOMAIN {
    reverse_proxy wg-easy:51821
}
EOF

# 7. Create docker-compose.yml
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
      # INSECURE=true is now removed
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

# 8. Firewall Adjustments
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw allow 51820/udp
sudo ufw --force enable

# 9. Launch
echo "--- Starting Docker Containers ---"
sudo docker compose up -d

echo "--- Setup Complete! ---"
echo "Access your UI at: https://$WG_DOMAIN"
