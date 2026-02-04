# WaSup (Chatwoot) Deployment Guide

This guide covers deploying WaSup (customized Chatwoot) on an Ubuntu VM - works for Azure, AWS, DigitalOcean, or any VPS provider.

## Prerequisites

- Ubuntu 22.04 or 24.04 LTS
- Minimum 2 vCPU, 4GB RAM, 40GB storage
- Domain name pointed to your server's IP (e.g., `app.yourdomain.com`)
- SSH access to the server

---

## 1. Initial Server Setup

### Connect to your server

```bash
ssh root@YOUR_SERVER_IP
```

### Update system and install essentials

```bash
apt update && apt upgrade -y
apt install -y curl wget git nginx certbot python3-certbot-nginx ufw
```

### Create a non-root user (recommended)

```bash
adduser wasup
usermod -aG sudo wasup
su - wasup
```

### Configure firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

---

## 2. Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose plugin
sudo apt install -y docker-compose-plugin

# Log out and back in for group changes
exit
ssh wasup@YOUR_SERVER_IP

# Verify installation
docker --version
docker compose version
```

---

## 3. Clone the Repository

```bash
cd ~
git clone https://github.com/YOUR_REPO/wasup.git
cd wasup/chatwoot
```

Or copy your local files to the server:

```bash
# From your local machine
rsync -avz --progress /home/wasup/Desktop/wasup/chatwoot/ wasup@YOUR_SERVER_IP:~/wasup/chatwoot/
```

---

## 4. Configure Environment

### Create production environment file

```bash
cd ~/wasup/chatwoot
cp .env .env.production
nano .env.production
```

### Update these critical values:

```bash
#=============================================================================
# WaSup Production Environment
#=============================================================================

# Application - UPDATE THIS TO YOUR DOMAIN
SECRET_KEY_BASE=<generate-new-key-see-below>
FRONTEND_URL=https://app.yourdomain.com
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
LOG_LEVEL=info

# Database - USE STRONG PASSWORDS
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=<generate-strong-password>
POSTGRES_DATABASE=chatwoot_production

# Redis - USE STRONG PASSWORD
REDIS_URL=redis://:<redis-password>@redis:6379
REDIS_PASSWORD=<generate-strong-password>

# Sidekiq
SIDEKIQ_CONCURRENCY=10

# Storage
ACTIVE_STORAGE_SERVICE=local

# Email (Required for password resets, notifications)
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_DOMAIN=yourdomain.com
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true
MAILER_SENDER_EMAIL=WaSup <noreply@yourdomain.com>

# WhatsApp Cloud API
WHATSAPP_CLOUD_BASE_URL=https://graph.facebook.com

# Security
ENABLE_ACCOUNT_SIGNUP=false
```

### Generate secure keys

```bash
# Generate SECRET_KEY_BASE
openssl rand -hex 64

# Generate POSTGRES_PASSWORD
openssl rand -hex 32

# Generate REDIS_PASSWORD
openssl rand -hex 32
```

---

## 5. Update Docker Compose for Production

Create or update `docker-compose.production.yaml`:

```bash
nano docker-compose.production.yaml
```

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USERNAME}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DATABASE}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    restart: always
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  rails:
    image: wasup:production
    build:
      context: .
      dockerfile: Dockerfile
      target: rails
    restart: always
    env_file: .env.production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - storage_data:/app/storage
      - public_data:/app/public
    command: ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

  sidekiq:
    image: wasup:production
    build:
      context: .
      dockerfile: Dockerfile
      target: sidekiq
    restart: always
    env_file: .env.production
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - storage_data:/app/storage

volumes:
  postgres_data:
  redis_data:
  storage_data:
  public_data:
```

---

## 6. Build and Deploy

### Build the Docker images

```bash
cd ~/wasup/chatwoot
docker compose -f docker-compose.production.yaml build
```

### Start the services

```bash
docker compose -f docker-compose.production.yaml up -d
```

### Run database migrations

```bash
docker compose -f docker-compose.production.yaml exec rails bundle exec rails db:prepare
```

### Verify services are running

```bash
docker compose -f docker-compose.production.yaml ps
docker compose -f docker-compose.production.yaml logs rails --tail=50
```

---

## 7. Configure Nginx Reverse Proxy

### Create Nginx configuration

```bash
sudo nano /etc/nginx/sites-available/wasup
```

```nginx
upstream wasup {
    server 127.0.0.1:3000;
}

server {
    listen 80;
    server_name app.yourdomain.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.yourdomain.com;

    # SSL will be configured by certbot
    
    client_max_body_size 50M;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://wasup;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_redirect off;
    }

    # WebSocket support for ActionCable
    location /cable {
        proxy_pass http://wasup;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    # Webhooks endpoint for WhatsApp
    location /webhooks {
        proxy_pass http://wasup;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Enable the site

```bash
sudo ln -s /etc/nginx/sites-available/wasup /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 8. Setup SSL with Let's Encrypt

```bash
sudo certbot --nginx -d app.yourdomain.com
```

Follow the prompts to complete SSL setup. Certbot will automatically configure Nginx.

### Auto-renewal

```bash
# Test renewal
sudo certbot renew --dry-run

# Certbot adds auto-renewal by default
sudo systemctl status certbot.timer
```

---

## 9. Configure WhatsApp Webhooks

Now that your server is publicly accessible, configure Meta webhooks:

### Get your webhook URL

Your webhook URL is:
```
https://app.yourdomain.com/webhooks/whatsapp/YOUR_PHONE_NUMBER_ID
```

### Get your verify token

```bash
docker compose -f docker-compose.production.yaml exec postgres \
  psql -U postgres -d chatwoot_production \
  -c "SELECT phone_number, provider_config->>'webhook_verify_token' as token FROM channel_whatsapp;"
```

### Configure in Meta Developer Console

1. Go to [Meta Developer Console](https://developers.facebook.com/)
2. Select your app → WhatsApp → Configuration
3. Under **Webhook**, click **Edit**
4. Enter:
   - **Callback URL**: `https://app.yourdomain.com/webhooks/whatsapp/YOUR_PHONE_NUMBER_ID`
   - **Verify Token**: (from the query above)
5. Click **Verify and Save**
6. Subscribe to these webhook fields:
   - `messages`
   - `message_template_status_update`
   - `messaging_postbacks`

---

## 10. Create Admin User

```bash
docker compose -f docker-compose.production.yaml exec rails bundle exec rails console
```

In the Rails console:

```ruby
# Create super admin account
account = Account.create!(name: 'Your Company')
user = User.create!(
  email: 'admin@yourdomain.com',
  password: 'your-secure-password',
  name: 'Admin',
  confirmed_at: Time.current
)
AccountUser.create!(
  account: account,
  user: user,
  role: :administrator
)
SuperAdmin.create!(email: user.email)
exit
```

---

## 11. Maintenance Commands

### View logs

```bash
# All services
docker compose -f docker-compose.production.yaml logs -f

# Specific service
docker compose -f docker-compose.production.yaml logs -f rails
docker compose -f docker-compose.production.yaml logs -f sidekiq
```

### Restart services

```bash
docker compose -f docker-compose.production.yaml restart
docker compose -f docker-compose.production.yaml restart rails
```

### Update application

```bash
cd ~/wasup/chatwoot

# Pull latest code
git pull origin main

# Rebuild and restart
docker compose -f docker-compose.production.yaml build
docker compose -f docker-compose.production.yaml up -d

# Run migrations if needed
docker compose -f docker-compose.production.yaml exec rails bundle exec rails db:migrate
```

### Backup database

```bash
# Create backup
docker compose -f docker-compose.production.yaml exec postgres \
  pg_dump -U postgres chatwoot_production > backup_$(date +%Y%m%d_%H%M%S).sql

# Restore backup
cat backup_file.sql | docker compose -f docker-compose.production.yaml exec -T postgres \
  psql -U postgres chatwoot_production
```

### Access Rails console

```bash
docker compose -f docker-compose.production.yaml exec rails bundle exec rails console
```

### Access database

```bash
docker compose -f docker-compose.production.yaml exec postgres \
  psql -U postgres chatwoot_production
```

---

## 12. Azure-Specific Setup

If deploying on Azure VM:

### Create VM

1. Go to Azure Portal → Create Resource → Virtual Machine
2. Select:
   - **Image**: Ubuntu Server 22.04 LTS
   - **Size**: Standard_B2s (2 vCPU, 4GB RAM) or larger
   - **Authentication**: SSH public key
3. Create and wait for deployment

### Configure Networking

1. Go to VM → Networking → Add inbound port rule
2. Add rules for:
   - Port 80 (HTTP)
   - Port 443 (HTTPS)
   - Port 22 (SSH) - restrict to your IP

### Attach Data Disk (recommended)

1. Go to VM → Disks → Add data disk
2. Create new disk (64GB+ recommended)
3. Mount the disk:

```bash
# Find the disk
lsblk

# Format and mount
sudo mkfs.ext4 /dev/sdc
sudo mkdir /data
sudo mount /dev/sdc /data

# Add to fstab for persistence
echo '/dev/sdc /data ext4 defaults 0 2' | sudo tee -a /etc/fstab

# Move Docker data to new disk
sudo systemctl stop docker
sudo mv /var/lib/docker /data/docker
sudo ln -s /data/docker /var/lib/docker
sudo systemctl start docker
```

### Setup Azure DNS (optional)

1. Go to Azure DNS → Create zone
2. Add A record pointing to VM's public IP
3. Update your domain registrar's nameservers to Azure DNS

---

## 13. Monitoring & Alerts

### Setup basic monitoring

```bash
# Install monitoring tools
sudo apt install -y htop iotop

# Check resource usage
htop
docker stats
```

### Setup log rotation

```bash
sudo nano /etc/logrotate.d/docker
```

```
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=50M
    missingok
    delaycompress
    copytruncate
}
```

---

## Troubleshooting

### Services won't start

```bash
# Check logs
docker compose -f docker-compose.production.yaml logs

# Check if ports are in use
sudo netstat -tulpn | grep -E '3000|5432|6379'
```

### WhatsApp messages not arriving

1. Check webhook URL is correct and accessible
2. Verify SSL certificate is valid
3. Check Rails logs for webhook errors:
   ```bash
   docker compose -f docker-compose.production.yaml logs rails | grep webhook
   ```

### Database connection issues

```bash
# Check PostgreSQL is healthy
docker compose -f docker-compose.production.yaml exec postgres pg_isready

# Check environment variables
docker compose -f docker-compose.production.yaml exec rails env | grep POSTGRES
```

### 502 Bad Gateway

```bash
# Check if Rails is running
docker compose -f docker-compose.production.yaml ps
docker compose -f docker-compose.production.yaml logs rails --tail=100

# Check Nginx configuration
sudo nginx -t
sudo tail -f /var/log/nginx/error.log
```

---

## Security Checklist

- [ ] Changed all default passwords
- [ ] Disabled password SSH login (use keys only)
- [ ] Configured UFW firewall
- [ ] SSL certificate installed
- [ ] `ENABLE_ACCOUNT_SIGNUP=false` in production
- [ ] Database backups configured
- [ ] Monitoring alerts setup
- [ ] Regular security updates scheduled

---

## Quick Reference

| Service | Port | URL |
|---------|------|-----|
| Web App | 443 | https://app.yourdomain.com |
| Rails | 3000 | localhost:3000 (internal) |
| PostgreSQL | 5432 | localhost:5432 (internal) |
| Redis | 6379 | localhost:6379 (internal) |
| WhatsApp Webhook | 443 | https://app.yourdomain.com/webhooks/whatsapp/{phone_id} |

---

*Last updated: February 2026*
