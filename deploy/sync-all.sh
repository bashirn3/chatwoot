#!/usr/bin/env bash
# ============================================================
# wasup.co — Sync all working-tree changes to production
#
# Why this exists:
#   `deploy/hotfix.sh` only copies the files you explicitly list. Every
#   `docker compose up -d` recreates containers from the baked image and
#   wipes hotfixes that weren't included in that specific call. This
#   script ships EVERY code change (tracked-modified + new files under
#   safe directories) to the VM's rails + sidekiq containers, then does
#   a full frontend rebuild, then restarts both processes.
#
#   Safe to run repeatedly. Idempotent. The canonical way to restore
#   full state after a container recreation.
#
# Usage:
#   bash deploy/sync-all.sh                 # full sync + frontend rebuild
#   bash deploy/sync-all.sh --no-frontend   # skip the ~3min frontend rebuild
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_HOST="app-wasup.northeurope.cloudapp.azure.com"
ADMIN_USER="azureuser"
APP_DIR="/opt/chatwoot"
SSH_OPTS="-o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
COMPOSE="docker compose -f docker-compose.prod.yml"

REBUILD_FRONTEND=1
for arg in "$@"; do
  case "$arg" in
    --no-frontend) REBUILD_FRONTEND=0 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
  esac
done

remote() { ssh $SSH_OPTS "$ADMIN_USER@$VM_HOST" "$@"; }

cd "$REPO_ROOT"

echo '=== sync-all: collecting files ==='

# Build the file list:
#   - every tracked source file under INCLUDE_DIRS (so files committed
#     AFTER the image was baked still make it to the container)
#   - every untracked file under INCLUDE_DIRS not ignored by .gitignore
# Exclude explicitly: graphify-out, node_modules, tmp, .claude, build
# outputs, and any .env.* (secrets travel via .env.production → scp).
INCLUDE_DIRS=(app config db lib enterprise public/dashboard public/videos scripts)

FILE_LIST=$(mktemp)
trap 'rm -f "$FILE_LIST" /tmp/_sync_all.tar.gz' EXIT

{
  for d in "${INCLUDE_DIRS[@]}"; do
    [ -d "$d" ] || continue
    git ls-files -- "$d" 2>/dev/null || true
    git ls-files --others --exclude-standard -- "$d" 2>/dev/null || true
  done
  # Always include top-level Gemfile/Gemfile.lock if changed — Ruby bundler
  # needs them aligned with what the code imports.
  git diff --name-only HEAD -- Gemfile Gemfile.lock 2>/dev/null || true
} \
  | grep -vE '^(graphify-out|\.claude|node_modules|tmp|public/vite|public/packs)/' \
  | grep -vE '^\.env' \
  | sort -u \
  | while read -r f; do [ -f "$f" ] && echo "$f"; done \
  > "$FILE_LIST"

COUNT=$(wc -l < "$FILE_LIST" | tr -d ' ')
echo "  → $COUNT files to sync"
if [ "$COUNT" -eq 0 ]; then
  echo '  nothing to do'
  exit 0
fi

echo '=== sync-all: packing tarball ==='
tar --no-xattrs -czf /tmp/_sync_all.tar.gz -T "$FILE_LIST"
SIZE=$(ls -lh /tmp/_sync_all.tar.gz | awk '{print $5}')
echo "  → tarball $SIZE"

echo '=== sync-all: shipping to VM ==='
scp $SSH_OPTS /tmp/_sync_all.tar.gz "$ADMIN_USER@$VM_HOST":/tmp/_sync_all.tar.gz >/dev/null
echo '  → uploaded'

echo '=== sync-all: extracting into containers ==='
remote "cd $APP_DIR && \
  RAILS=\$($COMPOSE ps -q chatwoot-rails) && \
  SIDEKIQ=\$($COMPOSE ps -q chatwoot-sidekiq) && \
  for C in \$RAILS \$SIDEKIQ; do \
    docker cp /tmp/_sync_all.tar.gz \$C:/tmp/_sync_all.tar.gz && \
    docker exec \$C sh -c 'cd /app && tar xzf /tmp/_sync_all.tar.gz && rm /tmp/_sync_all.tar.gz'; \
  done && \
  rm /tmp/_sync_all.tar.gz" > /dev/null
echo '  → extracted to rails + sidekiq'

if [ "$REBUILD_FRONTEND" -eq 1 ]; then
  echo '=== sync-all: rebuilding frontend assets ==='
  remote "cd $APP_DIR && \
    RAILS=\$($COMPOSE ps -q chatwoot-rails) && \
    docker exec \$RAILS sh -c '\
      rm -rf /app/public/vite /app/tmp/cache/vite /app/tmp/cache/assets 2>/dev/null; \
      cd /app && pnpm vite build 2>&1 | tail -6; \
    '" || true
fi

echo '=== sync-all: restarting processes ==='
remote "cd $APP_DIR && \
  RAILS=\$($COMPOSE ps -q chatwoot-rails) && \
  SIDEKIQ=\$($COMPOSE ps -q chatwoot-sidekiq) && \
  docker exec \$RAILS sh -c 'touch /app/tmp/restart.txt 2>/dev/null || kill -USR2 1' && \
  docker restart \$SIDEKIQ > /dev/null"
echo '  → puma + sidekiq restarted'

echo
echo "sync-all complete — $COUNT files now live on prod."
