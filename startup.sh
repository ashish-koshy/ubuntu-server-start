#!/bin/bash
set -e

echo "--- Starting Machine Setup (Bridge Network) ---"

# 1. System Prep (Standard)
sudo apt update -y
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
sudo apt install -y git curl ufw net-tools ca-certificates

# 2. Docker Install (Standard)
if ! [ -x "$(command -v docker)" ]; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER || true
fi

# 3. Create the Docker Bridge Network
# This allows Caddy to find wg-easy by its container name
sudo docker network create vpn_network || true

# 4. Inputs & Defaults
read -p "Enter Domain [vpn.ackaboo.com]: " WG_DOMAIN
WG_DOMAIN=${WG_DOMAIN:-vpn.ackaboo.com}

read -p "Enter Email [reply@webmail.ackaboo.com]: " WG_EMAIL
WG_EMAIL=${WG_EMAIL:-reply@webmail.ackaboo.com}

read -s -p "Enter Admin Password: " WG_PASSWORD
echo ""

# 5. Generate Hash (Your proven method)
WGPW_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:14 node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('$WG_PASSWORD', 10));" | tr -d '\r\n')

# 6. Run WireGuard (Bridge Mode)
# We publish only the VPN UDP port to the host
sudo docker rm -f wg-easy || true
sudo docker run -d \
  --name wg-easy \
  --network vpn_network \
  --env WG_HOST="$WG_DOMAIN" \
  --env PASSWORD_HASH="${WGPW_HASH}" \
  --env PORT=8080 \
  --env WG_PORT=51000 \
  -p 51000:51000/udp \
  -v ~/.wg-easy:/etc/wireguard \
  -v /lib/modules:/lib/modules:ro \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --restart always \
  ghcr.io/wg-easy/wg-easy

# 7. Run Caddy (Bridge Mode)
# We publish 80/443 to the host and proxy to the wg-easy container name
sudo docker rm -f caddy || true
sudo docker run -d \
  --name caddy \
  --network vpn_network \
  -p 80:80 \
  -p 443:443 \
  -p 443:443/udp \
  --restart always \
  -v caddy_data:/data \
  -v caddy_config:/config \
  caddy:2.7-alpine \
  caddy reverse-proxy --from "$WG_DOMAIN" --to wg-easy:8080

# 8. Firewall
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 51000/udp
sudo ufw allow ssh
sudo ufw --force enable

echo "--- Setup Complete! ---"
echo "Admin: https://$WG_DOMAIN"
