#!/usr/bin/env bash
# ============================================================
# wasup.co — VM Setup Script
#
# Run locally. SSHs into the VM and installs Docker, nginx, etc.
#
# Usage:
#   bash deploy/setup-chatwoot-vm.sh [FQDN]
#   bash deploy/setup-chatwoot-vm.sh app-wasup.northeurope.cloudapp.azure.com
# ============================================================
set -euo pipefail

VM_HOST="${1:-app-wasup.northeurope.cloudapp.azure.com}"
ADMIN_USER="azureuser"
APP_DIR="/opt/chatwoot"

echo "========================================"
echo "  wasup.co — VM Setup"
echo "  Target: $VM_HOST"
echo "========================================"
echo ""

ssh -o StrictHostKeyChecking=accept-new "$ADMIN_USER@$VM_HOST" bash -s "$APP_DIR" "$VM_HOST" << 'REMOTE_SCRIPT'
set -euo pipefail

APP_DIR="$1"
VM_HOST="$2"

echo "[1/6] Updating system packages..."
sudo apt-get update -y && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "[2/6] Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
fi
echo "  Docker $(docker --version)"

echo "[3/6] Installing Docker Compose plugin..."
sudo apt-get install -y docker-compose-plugin
echo "  $(docker compose version)"

echo "[4/6] Installing nginx + certbot..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

echo "[5/6] Configuring nginx..."
sudo tee /etc/nginx/sites-available/chatwoot > /dev/null <<NGINXEOF
server {
    listen 80;
    server_name $VM_HOST;

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXEOF

sudo ln -sf /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

echo "[6/6] Creating app directory..."
sudo mkdir -p "$APP_DIR"
sudo chown "$USER:$USER" "$APP_DIR"

echo ""
echo "========================================"
echo "  VM setup complete!"
echo "========================================"
echo "  App dir: $APP_DIR"
echo "  nginx: proxying :80 -> :3000"
echo ""
echo "  Next: bash deploy/deploy-chatwoot.sh $VM_HOST"
echo ""
REMOTE_SCRIPT

echo "VM setup complete."
