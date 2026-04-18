#!/usr/bin/env bash
# ============================================================
# Finisher — switch Typebot builder to https://builder.wasup.co
#
# Run on the VM after you've added the DNS A record:
#   builder.wasup.co → 52.236.62.164
#
# What this does (idempotent):
#   1. Waits until builder.wasup.co resolves to this VM's IP
#   2. Issues a Let's Encrypt cert via certbot --nginx
#   3. Writes the new nginx config:
#        - builder.wasup.co:443 → typebot-builder, with UI lockdown
#        - keeps platform.wasup.co:443 → chatwoot
#        - removes the :3001 block (no longer needed)
#   4. Updates /opt/chatwoot/.env:
#        TYPEBOT_BUILDER_URL=https://builder.wasup.co
#   5. Restarts the typebot-builder container so NEXTAUTH_URL picks up
#   6. Reloads nginx
# ============================================================
set -euo pipefail

TARGET_IP="52.236.62.164"
DOMAIN="builder.wasup.co"
EMAIL="admin@wasup.co"
APP_DIR="/opt/chatwoot"
NGINX_CONF="/etc/nginx/sites-enabled/chatwoot"

echo "==> 1. Checking DNS for $DOMAIN ..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  RESOLVED=$(dig +short "$DOMAIN" A | tail -n1)
  if [[ "$RESOLVED" == "$TARGET_IP" ]]; then
    echo "    OK: $DOMAIN → $RESOLVED"
    break
  fi
  echo "    attempt $i: got '$RESOLVED', want '$TARGET_IP' — sleeping 10s"
  sleep 10
  if [[ $i -eq 10 ]]; then
    echo "ERROR: DNS still not pointing to $TARGET_IP. Add the A record at GoDaddy and retry."
    exit 1
  fi
done

echo "==> 2. Issuing Let's Encrypt cert for $DOMAIN ..."
sudo certbot certonly --nginx -d "$DOMAIN" \
  --non-interactive --agree-tos --email "$EMAIL" --keep-until-expiring

echo "==> 3. Writing new nginx config ..."
sudo tee "$NGINX_CONF" >/dev/null <<'NGINX_CONF'
server {
    server_name app-wasup.northeurope.cloudapp.azure.com platform.wasup.co;
    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    listen 443 ssl;

    location = /bridge-dashboard {
        alias /opt/chatwoot/public/bridge-dashboard.html;
        default_type text/html;
    }

    location /bridge-api/ {
        proxy_pass http://127.0.0.1:3003/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-API-Key change-me;
    }

    ssl_certificate /etc/letsencrypt/live/platform.wasup.co/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/platform.wasup.co/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    if ($host = platform.wasup.co) { return 301 https://$host$request_uri; }
    if ($host = app-wasup.northeurope.cloudapp.azure.com) { return 301 https://$host$request_uri; }
    if ($host = builder.wasup.co) { return 301 https://$host$request_uri; }
    listen 80;
    server_name app-wasup.northeurope.cloudapp.azure.com platform.wasup.co builder.wasup.co;
    return 404;
}

# =============================================================
# Typebot Builder — https://builder.wasup.co
# =============================================================
server {
    listen 443 ssl;
    server_name builder.wasup.co;
    client_max_body_size 50M;

    ssl_certificate /etc/letsencrypt/live/builder.wasup.co/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/builder.wasup.co/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location = /chatwoot-auth {
        add_header Set-Cookie "__Secure-authjs.session-token=$arg_token; Path=/; Max-Age=31536000; Secure; HttpOnly; SameSite=Lax" always;
        add_header Set-Cookie "authjs.session-token=$arg_token; Path=/; Max-Age=31536000; Secure; HttpOnly; SameSite=Lax" always;
        add_header Set-Cookie "__Secure-next-auth.session-token=$arg_token; Path=/; Max-Age=31536000; Secure; HttpOnly; SameSite=Lax" always;
        add_header Set-Cookie "next-auth.session-token=$arg_token; Path=/; Max-Age=31536000; Secure; HttpOnly; SameSite=Lax" always;
        return 302 $arg_redirect;
    }

    location / {
        proxy_pass http://127.0.0.1:3101;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Accept-Encoding "";

        sub_filter_once on;
        sub_filter '</head>' '<style>:root{--chakra-colors-orange-50:#f8fafc!important;--chakra-colors-orange-100:#f1f5f9!important;--chakra-colors-orange-200:#e2e8f0!important;--chakra-colors-orange-300:#cbd5e1!important;--chakra-colors-orange-400:#94a3b8!important;--chakra-colors-orange-500:#64748b!important;--chakra-colors-orange-600:#475569!important;--chakra-colors-orange-700:#334155!important;--chakra-colors-orange-800:#1e293b!important;--chakra-colors-orange-900:#0f172a!important}</style><script>(function(){function hide(el){if(el&&el.style.display!=="none")el.style.display="none"}function has(s,sub){return s&&s.indexOf(sub)>=0}function kill(){var hdr=document.getElementById("editor-header")||document.querySelector("header")||document.body;if(!hdr)return;var els=hdr.querySelectorAll("a,button");for(var i=0;i<els.length;i++){var el=els[i];var t=(el.textContent||"").trim();var h=(el.getAttribute&&el.getAttribute("href"))||"";var tid=(el.getAttribute&&el.getAttribute("data-testid"))||"";if(t==="Flow"||t==="Theme"||t==="Settings"||t==="Share"||t==="Results")hide(el);if(has(h,"/theme")||has(h,"/share")||has(h,"/results")||has(h,"/settings"))hide(el);if(has(tid,"share-tab")||has(tid,"theme-tab")||has(tid,"results-tab")||has(tid,"settings-tab")||has(tid,"share-button"))hide(el);if(h==="/typebots"||h==="/workspaces"||has(h,"/register")||has(h,"/signin")||has(h,"/signup"))hide(el);if(has(t,"Try Typebot")||has(t,"Upgrade")||has(t,"Pricing"))hide(el)}var extras=document.querySelectorAll("a");for(var j=0;j<extras.length;j++){var a=extras[j];var eh=(a.getAttribute&&a.getAttribute("href"))||"";if(has(eh,"typebot.io")&&!has(eh,"docs"))hide(a);if(has(eh,"/pricing")||has(eh,"/upgrade")||has(eh,"/billing")||has(eh,"/templates"))hide(a)}}var mo=new MutationObserver(kill);function start(){kill();mo.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:["href","class"]})}if(document.readyState==="complete"||document.readyState==="interactive")start();else document.addEventListener("DOMContentLoaded",start);setInterval(kill,500)})();</script></head>';
    }
}

# =============================================================
# Typebot Viewer (:3002) — kept on its own port for embeds
# =============================================================
server {
    listen 3002 ssl;
    server_name app-wasup.northeurope.cloudapp.azure.com platform.wasup.co;
    client_max_body_size 50M;

    ssl_certificate /etc/letsencrypt/live/app-wasup.northeurope.cloudapp.azure.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app-wasup.northeurope.cloudapp.azure.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:3102;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
NGINX_CONF

echo "==> 4. Testing nginx config ..."
sudo nginx -t

echo "==> 5. Updating $APP_DIR/.env ..."
cd "$APP_DIR"
sudo sed -i 's|^TYPEBOT_BUILDER_URL=.*|TYPEBOT_BUILDER_URL=https://builder.wasup.co|' .env
grep '^TYPEBOT_BUILDER_URL=' .env

echo "==> 6. Reloading nginx ..."
sudo systemctl reload nginx

echo "==> 7. Recreating typebot-builder container with new NEXTAUTH_URL ..."
sudo docker compose -f docker-compose.prod.yml up -d typebot-builder

echo "==> 8. Recreating chatwoot-rails so frontend sees new builder URL ..."
# Only touch rails so the asset/env refresh happens; don't wipe container-local hotfixes
sudo docker compose -f docker-compose.prod.yml restart chatwoot-rails

echo ""
echo "DONE. Test:  https://builder.wasup.co/"
echo "Then click Edit on a workflow in the dashboard — it should open on builder.wasup.co."
