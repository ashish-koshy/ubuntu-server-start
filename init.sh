#!/bin/bash
set -e
echo "--- Installing Docker and common tools ---"
sudo apt update -y
sudo apt install -y net-tools ca-certificates curl git ufw

# Official Docker Installation Method
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

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER || true

echo "--- Docker setup complete ---"

echo "--- Adding GitHub SSH keys ---"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

GITHUB_KEYS=$(curl -fsSL https://github.com/ashish-koshy.keys)
while IFS= read -r key; do
    if [ -n "$key" ] && ! grep -qF "$key" ~/.ssh/authorized_keys; then
        echo "$key" >> ~/.ssh/authorized_keys
        echo "Added key: ${key:0:50}..."
    fi
done <<< "$GITHUB_KEYS"
echo "--- SSH keys setup complete ---"

read -p "Do you want to setup a Cloudflared tunnel with Docker? (y/n): " SETUP_CLOUDFLARED
if [[ "$SETUP_CLOUDFLARED" =~ ^[Yy]$ ]]; then
    read -p "Enter your Cloudflare tunnel token: " TUNNEL_TOKEN
    if [ -n "$TUNNEL_TOKEN" ]; then
        echo "--- Setting up Cloudflared tunnel ---"
        docker run -d --name cloudflared --restart unless-stopped \
            cloudflare/cloudflared:latest tunnel --no-autoupdate run \
            --token "$TUNNEL_TOKEN"
        echo "--- Cloudflared tunnel setup complete ---"
    else
        echo "No token provided, skipping Cloudflared setup."
    fi
fi

read -p "Do you want to enable swap (2GB)? (y/n): " SETUP_SWAP
if [[ "$SETUP_SWAP" =~ ^[Yy]$ ]]; then
    echo "--- Setting up swap ---"
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "--- Swap setup complete ---"
    free -h
fi
