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
echo "--- Installing Basic Tools ---"
sudo apt install -y git nano python3 python3-pip net-tools build-essential ufw ca-certificates curl

# 3. Setup SSH Public Keys (Idempotent)
echo "--- Configuring SSH Keys ---"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
curl -sL https://github.com/ashish-koshy.keys | while read -r key; do
    if ! grep -qF "$key" ~/.ssh/authorized_keys; then
        echo "$key" >> ~/.ssh/authorized_keys
    fi
done
chmod 600 ~/.ssh/authorized_keys

# 4. Configure UFW NAT (The "Back Door" Fix for AWS)
echo "--- Configuring UFW for NAT Masquerade ---"
sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
if ! grep -q "*nat" /etc/ufw/before.rules; then
    sudo sed -i '1i # NAT rules\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -o ens5 -j MASQUERADE\nCOMMIT\n' /etc/ufw/before.rules
fi

# 5. Standard Firewall Rules
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp      # Caddy HTTP
sudo ufw allow 443/tcp     # Caddy HTTPS
sudo ufw allow 443/udp     # Caddy HTTP/3
sudo ufw allow 51000/udp   # WireGuard UDP
sudo ufw --force enable

# 6. Install Docker Engine
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
sudo usermod -aG docker $USER || true

# 7. WireGuard Setup (Using your original working logic)
echo ""
read -p "Do you want to setup WireGuard (wg-easy)? (y/n): " install_wg
if [[ "$install_wg" =~ ^[Yy]$ ]]; then    
    read -p "Enter Domain [vpn.ackaboo.com]: " WG_DOMAIN
    WG_DOMAIN=${WG_DOMAIN:-vpn.ackaboo.com}
    
    read -p "Enter Email [reply@webmail.ackaboo.com]: " WG_EMAIL
    WG_EMAIL=${WG_EMAIL:-reply@webmail.ackaboo.com}

    read -s -p "Enter Admin Password: " WG_PASSWORD
    echo ""

    echo "--- Generating Secure Password Hash ---"
    WGPW_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:14 node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('$WG_PASSWORD', 10));" | tr -d '\r\n')
    
    sudo docker rm -f wg-easy || true
    sudo docker run -d \
      --name wg-easy \
      --network host \
      --env WG_HOST="$WG_DOMAIN" \
      --env PASSWORD_HASH="${WGPW_HASH}" \
      --env WG_PORT=51000 \
      --env WG_MTU=1280 \
      -v ~/.wg-easy:/etc/wireguard \
      -v /lib/modules:/lib/modules:ro \
      --cap-add=NET_ADMIN \
      --cap-add=SYS_MODULE \
      --restart always \
      ghcr.io/wg-easy/wg-easy

    # 8. Caddy Setup (Integrated via docker run to avoid YAML issues)
    echo "--- Setting up Caddy Reverse Proxy ---"
    sudo docker rm -f caddy || true
    sudo docker run -d \
      --name caddy \
      --network host \
      --restart always \
      -v caddy_data:/data \
      -v caddy_config:/config \
      caddy:2.7-alpine \
      caddy reverse-proxy --from "$WG_DOMAIN" --to localhost:51821
fi

# 9. Cloudflared Tunnel Setup
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

echo "--- Setup Complete! ---"
echo "Login at: https://$WG_DOMAIN"
