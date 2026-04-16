#!/usr/bin/env bash
# ============================================================
# Provision Azure VM for wasup.co (Chatwoot) deployment
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#
# Usage:
#   bash deploy/provision-chatwoot-azure.sh
#
# Creates:
#   1. VM in existing whatsapp-ai-rg resource group
#   2. DNS label: app-wasup.northeurope.cloudapp.azure.com
#   3. Opens ports 22, 80, 443
# ============================================================
set -euo pipefail

RESOURCE_GROUP="${AZURE_RG:-whatsapp-ai-rg}"
LOCATION="${AZURE_LOCATION:-northeurope}"
VM_NAME="${AZURE_VM_NAME:-app-wasup}"
VM_SIZE="${AZURE_VM_SIZE:-Standard_B2ms}"
DNS_LABEL="app-wasup"
ADMIN_USER="azureuser"

echo "========================================"
echo "  wasup.co — Azure VM Provisioning"
echo "========================================"
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  Location:        $LOCATION"
echo "  VM:              $VM_NAME ($VM_SIZE)"
echo "  DNS:             $DNS_LABEL.$LOCATION.cloudapp.azure.com"
echo "========================================"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 1

# ---- 1. Ensure resource group exists ----
echo "[1/4] Ensuring resource group exists..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table 2>/dev/null || true

# ---- 2. Create VM ----
echo "[2/4] Creating VM..."
az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --image Canonical:ubuntu-24_04-lts:server:latest \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USER" \
    --generate-ssh-keys \
    --public-ip-sku Standard \
    --output table

# ---- 3. Set DNS label ----
echo "[3/4] Setting DNS label..."
IP_NAME=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --show-details \
    --query "publicIps" -o tsv | head -1)

PUBLIC_IP_ID=$(az network public-ip list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?ipAddress=='$IP_NAME'].id" -o tsv)

az network public-ip update \
    --ids "$PUBLIC_IP_ID" \
    --dns-name "$DNS_LABEL" \
    --output table

VM_FQDN="$DNS_LABEL.$LOCATION.cloudapp.azure.com"
echo "  FQDN: $VM_FQDN"

# ---- 4. Open ports ----
echo "[4/4] Opening ports 80, 443..."
az vm open-port --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --port 80 --priority 1001 --output table 2>/dev/null || true
az vm open-port --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --port 443 --priority 1002 --output table 2>/dev/null || true

# ---- Summary ----
echo ""
echo "========================================"
echo "  VM provisioned!"
echo "========================================"
echo ""
echo "  FQDN:  $VM_FQDN"
echo "  SSH:   ssh $ADMIN_USER@$VM_FQDN"
echo ""
echo "  Next steps:"
echo "    1. bash deploy/setup-chatwoot-vm.sh $VM_FQDN"
echo "    2. bash deploy/deploy-chatwoot.sh $VM_FQDN"
echo ""

cat > /tmp/chatwoot-azure-env.txt <<ENVEOF
VM_FQDN=$VM_FQDN
SSH_CMD=ssh $ADMIN_USER@$VM_FQDN
ENVEOF
echo "  Saved to /tmp/chatwoot-azure-env.txt"
