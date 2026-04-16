#!/usr/bin/env bash
# ============================================================
# wasup.co — Deploy to Azure VM
#
# Speed: multi-stage Dockerfile caches gems. Frontend-only
#        changes rebuild in ~5 min on the VM.
#
# Safety: uses a file lock on the VM so two agents/deploys
#         can't overlap. Second deploy waits or aborts.
#
# Usage:
#   bash deploy/deploy-chatwoot.sh              # full deploy
#   bash deploy/deploy-chatwoot.sh --skip-build # sync + restart only
#   bash deploy/deploy-chatwoot.sh --logs       # tail live logs
#   bash deploy/deploy-chatwoot.sh --status     # check VM services
#   bash deploy/deploy-chatwoot.sh --unlock     # force-clear a stale lock
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_HOST="app-wasup.northeurope.cloudapp.azure.com"
ADMIN_USER="azureuser"
APP_DIR="/opt/chatwoot"
IMAGE_NAME="chatwoot-whitelabel:latest"
LOCK_FILE="/tmp/chatwoot-deploy.lock"
LOCK_MAX_AGE=900
SSH_OPTS="-o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
COMPOSE="docker compose -f docker-compose.prod.yml"

remote() { ssh $SSH_OPTS "$ADMIN_USER@$VM_HOST" "$@"; }

# ---- Shortcuts ----
case "${1:-}" in
  --logs)
    remote "cd $APP_DIR && $COMPOSE logs -f --tail 50 chatwoot-rails chatwoot-sidekiq"
    exit 0 ;;
  --status)
    remote "cd $APP_DIR && $COMPOSE ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null"
    exit 0 ;;
  --unlock)
    remote "rm -f $LOCK_FILE" && echo "Lock cleared." ; exit 0 ;;
esac

SKIP_BUILD=false
[[ "${1:-}" == "--skip-build" ]] && SKIP_BUILD=true

echo "========================================"
echo "  wasup.co — Deploy"
echo "  VM: $VM_HOST"
echo "========================================"
echo ""

# ============================================================
# Step 0 — Acquire deploy lock on VM
# ============================================================
echo "[0/5] Acquiring deploy lock..."
LOCK_RESULT=$(remote bash << LOCK_SCRIPT
LOCK_FILE="$LOCK_FILE"
if [ -f "\$LOCK_FILE" ]; then
    LOCK_AGE=\$(( \$(date +%s) - \$(stat -c %Y "\$LOCK_FILE" 2>/dev/null || echo 0) ))
    if [ "\$LOCK_AGE" -lt $LOCK_MAX_AGE ]; then
        echo "LOCKED|\$(cat "\$LOCK_FILE" 2>/dev/null)"
        exit 0
    fi
fi
echo "\$(whoami)@\$(hostname) at \$(date '+%Y-%m-%d %H:%M:%S')" > "\$LOCK_FILE"
echo "OK"
LOCK_SCRIPT
)

if [[ "$LOCK_RESULT" == LOCKED\|* ]]; then
    OWNER="${LOCK_RESULT#LOCKED|}"
    echo ""
    echo "  BLOCKED — another deploy is in progress:"
    echo "    $OWNER"
    echo ""
    echo "  Wait for it to finish, or force-clear:"
    echo "    bash deploy/deploy-chatwoot.sh --unlock"
    exit 1
fi
echo "  Lock acquired."

cleanup_lock() { remote "rm -f $LOCK_FILE" 2>/dev/null || true; }
trap cleanup_lock EXIT

# ============================================================
# Step 1 — Sync codebase
# ============================================================
echo "[1/5] Syncing codebase..."
rsync -az --delete \
    --exclude '.git' \
    --exclude '.claude' \
    --exclude '.cursor' \
    --exclude 'node_modules' \
    --exclude 'tmp' \
    --exclude 'log' \
    --exclude 'storage' \
    --exclude '.devcontainer' \
    --exclude '.bundle' \
    --exclude 'coverage' \
    --exclude 'spec' \
    --exclude 'whatsapp-ai-framework/app/node_modules' \
    --exclude 'whatsapp-ai-framework/app/instances' \
    --exclude 'typebot-auth' \
    -e "ssh $SSH_OPTS" \
    "$REPO_ROOT/" "$ADMIN_USER@$VM_HOST:$APP_DIR/"
echo "  Done."

# ============================================================
# Step 2 — Copy production env as .env
# ============================================================
echo "[2/5] Setting environment..."
if [[ -f "$REPO_ROOT/.env.production" ]]; then
    scp $SSH_OPTS "$REPO_ROOT/.env.production" "$ADMIN_USER@$VM_HOST:$APP_DIR/.env" 2>/dev/null
    echo "  .env.production -> .env"
else
    echo "  WARNING: .env.production not found, using existing .env on VM."
fi

# ============================================================
# Step 3 — Build image on VM (gems are cached)
# ============================================================
if [[ "$SKIP_BUILD" == true ]]; then
    echo "[3/5] Skipping build (--skip-build)."
else
    echo "[3/5] Building Docker image on VM (gems cached unless Gemfile changed)..."
    START_TIME=$SECONDS
    remote "cd $APP_DIR && docker build -f docker/Dockerfile -t $IMAGE_NAME . 2>&1" | tail -40
    BUILD_SECS=$(( SECONDS - START_TIME ))
    echo "  Build done in ${BUILD_SECS}s."
fi

# ============================================================
# Step 4 — Restart services
# ============================================================
echo "[4/5] Restarting services..."
remote bash -s "$APP_DIR" << 'EOF'
set -euo pipefail
APP_DIR="$1"
cd "$APP_DIR"
COMPOSE="docker compose -f docker-compose.prod.yml"

$COMPOSE up -d --force-recreate chatwoot-rails chatwoot-sidekiq 2>&1

echo "  Waiting for Rails to boot..."
for i in $(seq 1 30); do
    sleep 2
    if $COMPOSE logs chatwoot-rails --since 5s 2>&1 | grep -q "Listening on"; then
        echo "  Puma is listening."
        break
    fi
    if $COMPOSE ps chatwoot-rails --format '{{.Status}}' 2>/dev/null | grep -q "Restarting"; then
        echo "  ERROR: Container is restart-looping."
        echo "    bash deploy/deploy-chatwoot.sh --logs"
        exit 1
    fi
done

echo "  Running migrations..."
$COMPOSE exec -T chatwoot-rails bundle exec rails db:chatwoot_prepare 2>&1 || true

docker image prune -f 2>/dev/null || true
EOF

# ============================================================
# Step 5 — Health check
# ============================================================
echo "[5/5] Health check..."
sleep 5
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$VM_HOST/app/login" || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "  OK — https://$VM_HOST (HTTP $HTTP_CODE)"
else
    echo "  HTTP $HTTP_CODE — may still be starting."
    echo "    bash deploy/deploy-chatwoot.sh --logs"
fi

TOTAL_SECS=$(( SECONDS ))
echo ""
echo "========================================"
echo "  Deploy complete! (${TOTAL_SECS}s)"
echo "========================================"
echo "  URL:  https://$VM_HOST"
echo "  Logs: bash deploy/deploy-chatwoot.sh --logs"
echo ""
