#!/bin/bash
set -e
echo "--- Starting Machine Setup (Bridge Network) ---"
# 1. Install Docker and common tools
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"
# 2. System Prep (WireGuard specific)
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
echo "--- Cleaning up ports and old containers ---"
sudo docker rm -f wg-easy caddy || true
sudo fuser -k 51000/udp || true
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
# Dashboard only accessible via VPN (bound to 10.8.0.1)
sudo docker rm -f wg-easy || true
sudo docker run -d \
  --name wg-easy \
  --env WG_HOST="$WG_DOMAIN" \
  --env PASSWORD_HASH="${WGPW_HASH}" \
  --env PORT=8080 \
  --env WG_PORT=51000 \
  -p 51000:51000/udp \
  -p 10.8.0.1:8080:8080 \
  -v ~/.wg-easy:/etc/wireguard \
  -v /lib/modules:/lib/modules:ro \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --restart always \
  ghcr.io/wg-easy/wg-easy
# 7. Firewall
sudo ufw allow 51000/udp
sudo ufw allow 53/udp
sudo ufw allow ssh
sudo ufw --force enable
# 8. Port redirect for restrictive networks (UDP 53 -> 51000)
# Allows clients on networks that block non-standard UDP ports to connect via port 53
# Add NAT rule to UFW's before.rules for persistence across reboots
NAT_RULE="*nat
:PREROUTING ACCEPT [0:0]
-A PREROUTING -p udp --dport 53 -j REDIRECT --to-port 51000
COMMIT"
if ! grep -q "PREROUTING -p udp --dport 53" /etc/ufw/before.rules 2>/dev/null; then
    echo "$NAT_RULE" | sudo tee -a /etc/ufw/before.rules > /dev/null
    sudo ufw reload
fi
echo "--- Setup Complete! ---"
echo "Admin: http://10.8.0.1:8080 (VPN only)"
echo "WireGuard ports: 51000/udp (standard), 53/udp (restrictive networks)"
