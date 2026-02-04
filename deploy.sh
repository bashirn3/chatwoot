#!/bin/bash

#=============================================================================
# WaSup (Modified Chatwoot) Deployment Script
# 
# Usage:
#   ./deploy.sh <command>
#
# Commands:
#   setup    - First-time setup (creates .env, builds, migrates)
#   start    - Start all services
#   stop     - Stop all services
#   restart  - Restart all services
#   update   - Pull code, rebuild, migrate, restart
#   build    - Build Docker images
#   migrate  - Run database migrations
#   status   - Show status of all services
#   logs     - Follow logs from all services
#   console  - Open Rails console
#   backup   - Backup database
#   restore  - Restore database from backup
#   clean    - Clean up unused Docker resources
#   help     - Show this help message
#=============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.wasup.yaml"
BACKUP_DIR="/opt/wasup/backups"
APP_NAME="wasup"

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if docker compose is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not available. Please install Docker Compose plugin."
        exit 1
    fi
}

# Check if compose file exists
check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "Compose file not found: $COMPOSE_FILE"
        print_info "Run './deploy.sh setup' first or copy the compose file from deploy folder"
        exit 1
    fi
}

# Generate secure random password
generate_password() {
    openssl rand -hex 32
}

# Generate secret key base
generate_secret() {
    openssl rand -hex 64
}

#=============================================================================
# Commands
#=============================================================================

cmd_setup() {
    print_info "Starting first-time setup..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Copy compose file if not exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        if [ -f "../documentation_for_wasup/deploy/docker-compose.production.yaml" ]; then
            cp ../documentation_for_wasup/deploy/docker-compose.production.yaml .
            print_success "Copied docker-compose.production.yaml"
        else
            print_error "Please copy docker-compose.production.yaml to this directory"
            exit 1
        fi
    fi
    
    # Create .env if not exists
    if [ ! -f ".env" ]; then
        print_info "Creating .env file..."
        
        SECRET_KEY=$(generate_secret)
        POSTGRES_PASS=$(generate_password)
        REDIS_PASS=$(generate_password)
        
        cat > .env << EOF
#=============================================================================
# WaSup Environment Configuration
# Generated on $(date)
#=============================================================================

# Application
SECRET_KEY_BASE=${SECRET_KEY}
FRONTEND_URL=http://localhost:3000
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
LOG_LEVEL=info

# Database
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_DATABASE=chatwoot_production

# Redis
REDIS_URL=redis://:${REDIS_PASS}@redis:6379
REDIS_PASSWORD=${REDIS_PASS}

# Sidekiq
SIDEKIQ_CONCURRENCY=10

# Storage (change to 'amazon' for S3)
ACTIVE_STORAGE_SERVICE=local

# Mailer (configure your SMTP settings)
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_DOMAIN=
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true
MAILER_SENDER_EMAIL=WaSup <noreply@yourdomain.com>

# WhatsApp Cloud API
WHATSAPP_CLOUD_BASE_URL=https://graph.facebook.com

# Optional: Sentry for error tracking
# SENTRY_DSN=

# Optional: NewRelic for APM
# NEW_RELIC_LICENSE_KEY=

#=============================================================================
# IMPORTANT: Update FRONTEND_URL and SMTP settings before production use!
#=============================================================================
EOF
        print_success "Created .env file with secure random passwords"
        print_warning "Please edit .env and configure your settings before starting"
        print_info "  nano .env"
    else
        print_info ".env file already exists, skipping..."
    fi
    
    # Build images
    print_info "Building Docker images (this may take a while)..."
    docker compose -f "$COMPOSE_FILE" build
    
    # Start postgres and redis first
    print_info "Starting database services..."
    docker compose -f "$COMPOSE_FILE" up -d postgres redis
    
    # Wait for postgres to be ready
    print_info "Waiting for PostgreSQL to be ready..."
    sleep 10
    
    until docker compose -f "$COMPOSE_FILE" exec postgres pg_isready -U postgres &> /dev/null; do
        print_info "Waiting for PostgreSQL..."
        sleep 2
    done
    
    # Run migrations
    print_info "Preparing database..."
    docker compose -f "$COMPOSE_FILE" run --rm rails bundle exec rails db:chatwoot_prepare
    
    print_success "Setup complete!"
    print_info "Start the application with: ./deploy.sh start"
}

cmd_start() {
    check_compose_file
    print_info "Starting services..."
    docker compose -f "$COMPOSE_FILE" up -d
    print_success "Services started!"
    print_info "Check status with: ./deploy.sh status"
}

cmd_stop() {
    check_compose_file
    print_info "Stopping services..."
    docker compose -f "$COMPOSE_FILE" down
    print_success "Services stopped!"
}

cmd_restart() {
    check_compose_file
    print_info "Restarting services..."
    docker compose -f "$COMPOSE_FILE" restart
    print_success "Services restarted!"
}

cmd_update() {
    check_compose_file
    print_info "Starting update process..."
    
    # Pull latest code
    if [ -d ".git" ]; then
        print_info "Pulling latest code..."
        git pull origin main || git pull origin master
    else
        print_warning "Not a git repository, skipping git pull"
    fi
    
    # Rebuild images
    print_info "Rebuilding Docker images..."
    docker compose -f "$COMPOSE_FILE" build
    
    # Run migrations
    print_info "Running database migrations..."
    docker compose -f "$COMPOSE_FILE" run --rm rails bundle exec rails db:chatwoot_prepare
    
    # Restart services
    print_info "Restarting services..."
    docker compose -f "$COMPOSE_FILE" up -d
    
    # Clean up old images
    print_info "Cleaning up old images..."
    docker image prune -f
    
    print_success "Update complete!"
}

cmd_build() {
    check_compose_file
    print_info "Building Docker images..."
    docker compose -f "$COMPOSE_FILE" build
    print_success "Build complete!"
}

cmd_migrate() {
    check_compose_file
    print_info "Running database migrations..."
    docker compose -f "$COMPOSE_FILE" run --rm rails bundle exec rails db:chatwoot_prepare
    print_success "Migrations complete!"
}

cmd_status() {
    check_compose_file
    print_info "Service status:"
    docker compose -f "$COMPOSE_FILE" ps
    echo ""
    print_info "Resource usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker compose -f "$COMPOSE_FILE" ps -q) 2>/dev/null || true
}

cmd_logs() {
    check_compose_file
    local service=${1:-}
    if [ -n "$service" ]; then
        docker compose -f "$COMPOSE_FILE" logs -f "$service"
    else
        docker compose -f "$COMPOSE_FILE" logs -f
    fi
}

cmd_console() {
    check_compose_file
    print_info "Opening Rails console..."
    docker compose -f "$COMPOSE_FILE" exec rails bundle exec rails c
}

cmd_backup() {
    check_compose_file
    mkdir -p "$BACKUP_DIR"
    
    BACKUP_FILE="$BACKUP_DIR/wasup_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    print_info "Creating database backup..."
    docker compose -f "$COMPOSE_FILE" exec -T postgres pg_dump -U postgres chatwoot_production > "$BACKUP_FILE"
    
    # Compress backup
    gzip "$BACKUP_FILE"
    
    print_success "Backup created: ${BACKUP_FILE}.gz"
    
    # Keep only last 7 backups
    print_info "Cleaning old backups (keeping last 7)..."
    ls -t "$BACKUP_DIR"/wasup_backup_*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm
    
    print_info "Current backups:"
    ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null || echo "No backups found"
}

cmd_restore() {
    check_compose_file
    
    if [ -z "$1" ]; then
        print_info "Available backups:"
        ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null || echo "No backups found"
        print_error "Usage: ./deploy.sh restore <backup_file.sql.gz>"
        exit 1
    fi
    
    BACKUP_FILE="$1"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        BACKUP_FILE="$BACKUP_DIR/$1"
    fi
    
    if [ ! -f "$BACKUP_FILE" ]; then
        print_error "Backup file not found: $1"
        exit 1
    fi
    
    print_warning "This will OVERWRITE the current database!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Restore cancelled"
        exit 0
    fi
    
    print_info "Restoring from: $BACKUP_FILE"
    
    # Decompress if needed
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        gunzip -k "$BACKUP_FILE"
        BACKUP_FILE="${BACKUP_FILE%.gz}"
    fi
    
    docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres chatwoot_production < "$BACKUP_FILE"
    
    print_success "Database restored!"
    print_info "You may need to restart services: ./deploy.sh restart"
}

cmd_clean() {
    print_info "Cleaning up Docker resources..."
    docker system prune -f
    docker image prune -f
    print_success "Cleanup complete!"
}

cmd_help() {
    echo "WaSup Deployment Script"
    echo ""
    echo "Usage: ./deploy.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  setup              First-time setup (creates .env, builds, migrates)"
    echo "  start              Start all services"
    echo "  stop               Stop all services"
    echo "  restart            Restart all services"
    echo "  update             Pull code, rebuild, migrate, restart"
    echo "  build              Build Docker images"
    echo "  migrate            Run database migrations"
    echo "  status             Show status of all services"
    echo "  logs [service]     Follow logs (optional: specific service)"
    echo "  console            Open Rails console"
    echo "  backup             Backup database"
    echo "  restore <file>     Restore database from backup"
    echo "  clean              Clean up unused Docker resources"
    echo "  help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh setup        # First-time setup"
    echo "  ./deploy.sh update       # Update after code changes"
    echo "  ./deploy.sh logs rails   # View only Rails logs"
    echo ""
}

#=============================================================================
# Main
#=============================================================================

check_docker

case "${1:-help}" in
    setup)
        cmd_setup
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    update)
        cmd_update
        ;;
    build)
        cmd_build
        ;;
    migrate)
        cmd_migrate
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs "$2"
        ;;
    console)
        cmd_console
        ;;
    backup)
        cmd_backup
        ;;
    restore)
        cmd_restore "$2"
        ;;
    clean)
        cmd_clean
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        print_error "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
