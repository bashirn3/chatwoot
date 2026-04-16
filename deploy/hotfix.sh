#!/usr/bin/env bash
# ============================================================
# wasup.co — Quick Hotfix (no image rebuild)
#
# Copies changed files directly into the running container(s)
# and restarts the relevant process.
#
# Speed:
#   Ruby changes  → ~10 seconds (copy + restart Puma)
#   Vue/JS changes → ~3-5 min (copy + recompile assets inside container)
#
# Usage:
#   bash deploy/hotfix.sh ruby app/controllers/api/v1/accounts/captain/scenarios_controller.rb
#   bash deploy/hotfix.sh ruby enterprise/app/controllers/...
#   bash deploy/hotfix.sh frontend   # syncs all frontend, recompiles assets
#   bash deploy/hotfix.sh frontend app/javascript/dashboard/routes/.../Index.vue
#   bash deploy/hotfix.sh restart    # just restart rails + sidekiq
#   bash deploy/hotfix.sh shell      # open a shell inside the rails container
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_HOST="app-wasup.northeurope.cloudapp.azure.com"
ADMIN_USER="azureuser"
APP_DIR="/opt/chatwoot"
SSH_OPTS="-o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
COMPOSE="docker compose -f docker-compose.prod.yml"

remote() { ssh $SSH_OPTS "$ADMIN_USER@$VM_HOST" "$@"; }

get_container() {
  remote "cd $APP_DIR && $COMPOSE ps -q chatwoot-rails"
}

usage() {
  echo "Usage:"
  echo "  bash deploy/hotfix.sh ruby <file1> [file2 ...]   Copy Ruby files, restart Puma"
  echo "  bash deploy/hotfix.sh frontend [file1 ...]        Copy frontend files, recompile assets"
  echo "  bash deploy/hotfix.sh restart                     Restart rails + sidekiq"
  echo "  bash deploy/hotfix.sh shell                       Shell into the rails container"
  echo ""
  echo "Examples:"
  echo "  bash deploy/hotfix.sh ruby app/controllers/api/v1/accounts/captain/scenarios_controller.rb"
  echo "  bash deploy/hotfix.sh ruby enterprise/app/controllers/some_controller.rb app/models/inbox.rb"
  echo "  bash deploy/hotfix.sh frontend app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue"
  echo "  bash deploy/hotfix.sh frontend  # syncs ALL frontend source and recompiles"
  exit 1
}

[[ $# -lt 1 ]] && usage
MODE="$1"
shift

case "$MODE" in
  # -------------------------------------------------------
  # Ruby hotfix: copy files into container, restart Puma
  # -------------------------------------------------------
  ruby)
    [[ $# -lt 1 ]] && { echo "Error: specify at least one file path (relative to repo root)."; exit 1; }

    CONTAINER=$(get_container)
    [[ -z "$CONTAINER" ]] && { echo "Error: chatwoot-rails container not running."; exit 1; }

    echo "=== Ruby hotfix ==="
    for FILE in "$@"; do
      LOCAL="$REPO_ROOT/$FILE"
      [[ ! -f "$LOCAL" ]] && { echo "  SKIP (not found): $FILE"; continue; }

      echo "  Copying $FILE ..."
      scp $SSH_OPTS "$LOCAL" "$ADMIN_USER@$VM_HOST:/tmp/_hotfix_file"
      remote "docker cp /tmp/_hotfix_file $CONTAINER:/app/$FILE && rm /tmp/_hotfix_file"
    done

    # Also copy into sidekiq container
    SIDEKIQ=$(remote "cd $APP_DIR && $COMPOSE ps -q chatwoot-sidekiq" 2>/dev/null || true)
    if [[ -n "$SIDEKIQ" ]]; then
      echo "  Syncing to sidekiq container..."
      for FILE in "$@"; do
        LOCAL="$REPO_ROOT/$FILE"
        [[ ! -f "$LOCAL" ]] && continue
        scp $SSH_OPTS "$LOCAL" "$ADMIN_USER@$VM_HOST:/tmp/_hotfix_file"
        remote "docker cp /tmp/_hotfix_file $SIDEKIQ:/app/$FILE && rm /tmp/_hotfix_file"
      done
    fi

    echo "  Restarting Puma..."
    remote "docker exec $CONTAINER touch /app/tmp/restart.txt 2>/dev/null || \
            docker exec $CONTAINER kill -USR2 1"
    if [[ -n "$SIDEKIQ" ]]; then
      echo "  Restarting Sidekiq..."
      remote "docker kill -s TSTP $SIDEKIQ && docker restart $SIDEKIQ"
    fi

    echo "  Done! Changes are live."
    ;;

  # -------------------------------------------------------
  # Frontend hotfix: copy files, recompile assets in container
  # -------------------------------------------------------
  frontend)
    CONTAINER=$(get_container)
    [[ -z "$CONTAINER" ]] && { echo "Error: chatwoot-rails container not running."; exit 1; }

    echo "=== Frontend hotfix ==="

    if [[ $# -gt 0 ]]; then
      for FILE in "$@"; do
        LOCAL="$REPO_ROOT/$FILE"
        [[ ! -f "$LOCAL" ]] && { echo "  SKIP (not found): $FILE"; continue; }
        echo "  Copying $FILE ..."
        scp $SSH_OPTS "$LOCAL" "$ADMIN_USER@$VM_HOST:/tmp/_hotfix_file"
        remote "docker cp /tmp/_hotfix_file $CONTAINER:/app/$FILE && rm /tmp/_hotfix_file"
      done
    else
      echo "  Creating frontend archive..."
      tar czf /tmp/_hotfix_frontend.tar.gz \
        -C "$REPO_ROOT" \
        app/javascript/ \
        app/views/ \
        package.json \
        pnpm-lock.yaml \
        tailwind.config.js \
        postcss.config.js \
        $([ -f "$REPO_ROOT/vite.config.ts" ] && echo "vite.config.ts") \
        $([ -f "$REPO_ROOT/vite.config.mjs" ] && echo "vite.config.mjs") \
        2>/dev/null

      echo "  Uploading to VM..."
      scp $SSH_OPTS /tmp/_hotfix_frontend.tar.gz "$ADMIN_USER@$VM_HOST:/tmp/_hotfix_frontend.tar.gz"
      rm -f /tmp/_hotfix_frontend.tar.gz

      echo "  Extracting into container..."
      remote "docker cp /tmp/_hotfix_frontend.tar.gz $CONTAINER:/tmp/_hotfix_frontend.tar.gz && \
              docker exec $CONTAINER sh -c 'cd /app && tar xzf /tmp/_hotfix_frontend.tar.gz && rm /tmp/_hotfix_frontend.tar.gz' && \
              rm -f /tmp/_hotfix_frontend.tar.gz"
    fi

    echo "  Checking if node_modules exist in container..."
    HAS_MODULES=$(remote "docker exec $CONTAINER sh -c '[ -d /app/node_modules ] && echo yes || echo no'" 2>/dev/null)
    if [[ "$HAS_MODULES" != "yes" ]]; then
      echo "  Installing frontend dependencies (first-time setup, ~2 min)..."
      HAS_PNPM=$(remote "docker exec $CONTAINER sh -c 'which pnpm >/dev/null 2>&1 && echo yes || echo no'" 2>/dev/null)
      if [[ "$HAS_PNPM" != "yes" ]]; then
        echo "  Installing pnpm..."
        remote "docker exec $CONTAINER sh -c 'ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && npm install -g pnpm@10.2.0'"
      fi
      remote "docker exec $CONTAINER sh -c 'cd /app && pnpm i --frozen-lockfile 2>&1' | tail -10"
    fi

    echo "  Clearing asset caches and recompiling (this takes a few minutes)..."
    remote "docker exec $CONTAINER sh -c '\
      rm -rf /app/tmp/vite /app/tmp/cache/vite /app/public/vite /app/public/packs /app/node_modules/.vite 2>/dev/null && \
      export SECRET_KEY_BASE=precompile_placeholder && \
      export RAILS_ENV=production && \
      export NODE_OPTIONS=\"--max-old-space-size=4096 --openssl-legacy-provider\" && \
      bundle exec rake assets:precompile 2>&1' | tail -20"

    echo "  Restarting Puma to serve new assets..."
    remote "docker exec $CONTAINER touch /app/tmp/restart.txt 2>/dev/null || \
            docker exec $CONTAINER kill -USR2 1"

    echo "  Done! Frontend changes are live."
    ;;

  # -------------------------------------------------------
  # Just restart
  # -------------------------------------------------------
  restart)
    echo "=== Restarting services ==="
    remote "cd $APP_DIR && $COMPOSE restart chatwoot-rails chatwoot-sidekiq"
    echo "  Done."
    ;;

  # -------------------------------------------------------
  # Shell into container
  # -------------------------------------------------------
  shell)
    echo "Opening shell in chatwoot-rails container..."
    remote -t "cd $APP_DIR && $COMPOSE exec chatwoot-rails sh"
    ;;

  *)
    usage
    ;;
esac
