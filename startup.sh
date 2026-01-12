#!/bin/bash
set -e

echo "--- Starting Machine Setup ---"

# 1. System Prep
sudo apt update -y
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 2. Tools & Docker (Standard Install)
sudo apt install -y git curl ufw ca-certificates build-essential
if ! [ -x "$(command -v docker)" ]; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
fi

mkdir -p ~/wireguard-stack
cd ~/wireguard-stack

# 3. WireGuard + Caddy Setup
echo ""
read -p "Setup WireGuard & Caddy? (y/n): " install_wg
if [[ "$install_wg" =~ ^[Yy]$ ]]; then    
    read -p "Domain (e.g., vpn.ackaboo.com): " WG_DOMAIN
    read -p "Email: " WG_EMAIL
    read -s -p "Admin Password: " WG_PASSWORD
    echo ""

    # Generate hash
    WGPW_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:latest node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('$WG_PASSWORD', 10));")
    
    # Create Caddyfile
    cat <<EOF > Caddyfile
{
    email $WG_EMAIL
}
$WG_DOMAIN {
    reverse_proxy wg-easy:51821
}
EOF

    # Create compose.yml - Using 'EOF' in quotes stops the password bug
    cat <<'EOF' > compose.yml
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
      - WG_HOST=${WG_HOST_PLACEHOLDER}
      - PASSWORD_HASH=${WG_PASS_PLACEHOLDER}
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

    # Manually inject the values to ensure the $ symbols in the hash are preserved
    sed -i "s|\${WG_HOST_PLACEHOLDER}|$WG_DOMAIN|g" compose.yml
    sed -i "s|\${WG_PASS_PLACEHOLDER}|$WGPW_HASH|g" compose.yml

    # Firewall
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 443/udp
    sudo ufw allow 51820/udp
    sudo ufw allow ssh
    sudo ufw --force enable

    sudo docker compose up -d
fi

# 4. Cloudflared (Optional)
read -p "Install Cloudflared? (y/n): " install_cf
if [[ "$install_cf" =~ ^[Yy]$ ]]; then
    read -p "Token: " CF_TOKEN
    sudo docker run -d --name cloudflared --network host --restart always cloudflare/cloudflared:latest tunnel --no-autoupdate run --token "$CF_TOKEN"
fi

echo "--- Setup Complete! ---"
