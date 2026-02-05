#!/bin/bash

#=============================================================================
# WaSup Deployment Script (Supabase Edition)
# 
# Usage:
#   ./deploy.sh build    - Build and start containers
#   ./deploy.sh start    - Start containers (without rebuild)
#   ./deploy.sh stop     - Stop all containers
#   ./deploy.sh restart  - Restart containers
#   ./deploy.sh logs     - View logs
#   ./deploy.sh migrate  - Run database migrations
#   ./deploy.sh console  - Open Rails console
#   ./deploy.sh status   - Check container status
#=============================================================================

COMPOSE_FILE="docker-compose.supabase.yaml"

set -e

case "$1" in
  build)
    echo "🔨 Building and starting WaSup with Supabase..."
    docker compose -f $COMPOSE_FILE build
    docker compose -f $COMPOSE_FILE up -d
    echo ""
    echo "⏳ Waiting for services to start..."
    sleep 10
    echo ""
    echo "🔄 Running database migrations..."
    docker compose -f $COMPOSE_FILE exec -T rails bundle exec rails db:prepare || true
    docker compose -f $COMPOSE_FILE exec -T rails bundle exec rails db:migrate || true
    echo ""
    echo "✅ WaSup is now running at http://localhost:3000"
    docker compose -f $COMPOSE_FILE ps
    ;;
  
  start)
    echo "🚀 Starting WaSup..."
    docker compose -f $COMPOSE_FILE up -d
    echo "✅ Started! Access at http://localhost:3000"
    ;;
  
  stop)
    echo "🛑 Stopping WaSup..."
    docker compose -f $COMPOSE_FILE down
    echo "✅ Stopped!"
    ;;
  
  restart)
    echo "🔄 Restarting WaSup..."
    docker compose -f $COMPOSE_FILE restart
    echo "✅ Restarted!"
    ;;
  
  logs)
    docker compose -f $COMPOSE_FILE logs -f
    ;;
  
  migrate)
    echo "🔄 Running database migrations..."
    docker compose -f $COMPOSE_FILE exec rails bundle exec rails db:migrate
    echo "✅ Migrations complete!"
    ;;
  
  console)
    echo "🔧 Opening Rails console..."
    docker compose -f $COMPOSE_FILE exec rails bundle exec rails console
    ;;
  
  status)
    docker compose -f $COMPOSE_FILE ps
    ;;
  
  *)
    echo "Usage: $0 {build|start|stop|restart|logs|migrate|console|status}"
    exit 1
    ;;
esac
