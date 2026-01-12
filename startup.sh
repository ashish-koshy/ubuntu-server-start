#!/bin/bash
set -e

echo "--- Starting Machine Setup ---"

# 1. System Prep & Docker Install
sudo apt update -y
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
sudo apt install -y git curl ufw ca-certificates build-essential

if ! [ -x "$(command -v docker)" ]; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
fi

# 2. Setup Project Directory
mkdir -p ~/wireguard-stack
cd ~/wireguard-stack

# 3. Inputs with Hardcoded Defaults
echo ""
read -p "Setup WireGuard & Caddy? (y/n): " install_wg
if [[ "$install_wg" =~ ^[Yy]$ ]]; then    
    read -p "Domain [vpn.ackaboo.com]: " WG_DOMAIN
    WG_DOMAIN=${WG_DOMAIN:-vpn.ackaboo.com}

    read -p "Email [reply@webmail.ackaboo.com]: " WG_EMAIL
    WG_EMAIL=${WG_EMAIL:-reply@webmail.ackaboo.com}

    read -s -p "Admin Password: " WG_PASSWORD
    echo ""

    echo "--- Generating Password Hash ---"
    # Generate hash and escape any backslashes/ampersands for sed
    RAW_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:latest node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('$WG_PASSWORD', 10));")
    WGPW_HASH=$(echo "$RAW_HASH" | sed 's/[&/\]/\\&/g')

    # 4. Create Caddyfile
    cat <<EOF > Caddyfile
{
    email $WG_EMAIL
}
$WG_DOMAIN {
    reverse_proxy wg-easy:51821
}
EOF

    # 5. Create compose.yml using a Template
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
      - WG_HOST=TEMPLATE_DOMAIN
      - PASSWORD_HASH=TEMPLATE_HASH
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

    # 6. Safe Injection
    sed -i "s|TEMPLATE_DOMAIN|$WG_DOMAIN|g" compose.yml
    sed -i "s|TEMPLATE_HASH|$WGPW_HASH|g" compose.yml

    # 7. Firewall & Launch
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 443/udp
    sudo ufw allow 51820/udp
    sudo ufw allow ssh
    sudo ufw --force enable

    sudo docker compose down --volumes || true
    sudo docker compose up -d
fi

echo "--- Setup Complete ---"
