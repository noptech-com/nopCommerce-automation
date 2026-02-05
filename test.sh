#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 domain db_name db_user db_pass admin_email [admin_pass_hash] [admin_salt]"
  exit 1
fi

DOMAIN="$1"
DB_NAME="$2"
DB_USER="$3"
DB_PASS="$4"
ADMIN_EMAIL="$5"
ADMIN_PASS_HASH="${6:-}"
ADMIN_SALT="${7:-}"

REMOTE_SCRIPT="/tmp/nop_provision.sh"

cat > /tmp/nop_provision.sh <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 domain db_name db_user db_pass admin_email [admin_pass_hash] [admin_salt]"
  exit 1
fi

DOMAIN="$1"
DB_NAME="$2"
DB_USER="$3"
DB_PASS="$4"
ADMIN_EMAIL="$5"
ADMIN_PASS_HASH="${6:-}"
ADMIN_SALT="${7:-}"

SERVER_IP="$(curl -4 -s ifconfig.me || true)"

export DEBIAN_FRONTEND=noninteractive

wait_dpkg_lock() {
  while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
  while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 1; done
  while sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do sleep 1; done
}

echo "==> Install prerequisites"
wait_dpkg_lock
sudo apt-get update -y
wait_dpkg_lock
sudo apt-get install -y curl unzip nginx postgresql postgresql-contrib libgdiplus certbot python3-certbot-nginx

echo "==> Install ASP.NET Core runtime"
wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
wait_dpkg_lock
sudo dpkg -i /tmp/packages-microsoft-prod.deb
wait_dpkg_lock
sudo apt-get update -y
wait_dpkg_lock
sudo apt-get install -y apt-transport-https aspnetcore-runtime-9.0

NOP_DIR="/var/www/$DOMAIN"

echo "==> Prepare Nginx (temporary HTTP only for certbot)"
sudo tee "/etc/nginx/sites-available/$DOMAIN" >/dev/null <<EOF
server {
  listen 80;
  server_name $DOMAIN www.$DOMAIN;
  client_max_body_size 250M;

  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }

  location / {
    return 200 "Certbot bootstrap for $DOMAIN\n";
  }
}
EOF

sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
sudo nginx -t
sudo systemctl reload nginx

echo "==> Obtain LetsEncrypt certificate (domain)"
sudo certbot --nginx -d "$DOMAIN" \
  --redirect --agree-tos --no-eff-email -m "$ADMIN_EMAIL"

echo "==> Write FINAL Nginx config (matches your desired structure)"
sudo tee "/etc/nginx/sites-available/$DOMAIN" >/dev/null <<EOF
# HTTPS server for main domain
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    client_max_body_size 250M;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://localhost:5001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Redirect www to non-www
server {
    listen 80;
    listen 443 ssl;
    server_name www.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    return 301 https://$DOMAIN\$request_uri;
}

# HTTP to HTTPS redirect for base domain
server {
    listen 80;
    server_name $DOMAIN;

    return 301 https://$DOMAIN\$request_uri;
}

# Redirect direct IP access to domain
server {
    listen 80;
    server_name $SERVER_IP;
    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 443 ssl;
    server_name $SERVER_IP;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    return 301 https://$DOMAIN\$request_uri;
}
EOF

sudo nginx -t
sudo systemctl reload nginx

echo "==> PostgreSQL: create user/db (no SUPERUSER)"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER;"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"

sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS citext;"
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

echo "==> Download nopCommerce (4.80.3) to $NOP_DIR"
sudo mkdir -p "$NOP_DIR"
cd "$NOP_DIR"
if [[ ! -f "Nop.Web.dll" ]]; then
  sudo wget -q https://github.com/nopSolutions/nopCommerce/releases/download/release-4.80.3/nopCommerce_4.80.3_NoSource_linux_x64.zip -O nop.zip
  sudo unzip -qq nop.zip
  sudo rm -f nop.zip
  sudo mkdir -p bin logs
fi

sudo chown -R www-data:www-data "$NOP_DIR"

echo "==> systemd service"
sudo tee "/etc/systemd/system/nopCommerce-$DOMAIN.service" >/dev/null <<EOF
[Unit]
Description=nopCommerce app running for $DOMAIN

[Service]
WorkingDirectory=$NOP_DIR
ExecStart=/usr/bin/dotnet $NOP_DIR/Nop.Web.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=nopCommerce-$DOMAIN
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false
Environment=ASPNETCORE_URLS=http://localhost:5001

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now "nopCommerce-$DOMAIN.service"

echo "==> Configure appsettings.json for PostgreSQL + proxy"
APPSET="$(find "$NOP_DIR" -maxdepth 3 -type f -iname 'appsettings.json' | head -n 1)"
echo "Using appsettings: $APPSET"
[[ -f "$APPSET" ]] || { echo "ERROR: appsettings.json not found under $NOP_DIR"; exit 1; }

sudo sed -i -z 's#"ConnectionString": ""#"ConnectionString": "Server=localhost;Database='"$DB_NAME"';User Id='"$DB_USER"';Password='"$DB_PASS"'"#' "$APPSET"
sudo sed -i 's/sqlserver/postgresql/' "$APPSET"

sudo sed -i '/"HostingConfig": {/,/}/c\
  "HostingConfig": {\
    "UseProxy": true,\
    "ForwardedProtoHeaderName": "X-Forwarded-Proto",\
    "ForwardedForHeaderName": "X-Forwarded-For",\
    "UseHttpXForwardedProto": "true",\
    "KnownProxies": "",\
    "KnownNetworks": "",\
    "Urls": "https://0.0.0.0:5001"\
  },' "$APPSET"

echo "==> Import default DB + set store/admin (if hashes provided)"
TMP_SQL="/tmp/nopcommerce48_default_db.sql"
wget -q https://raw.githubusercontent.com/noptech-com/nc-47-postgre-default/refs/heads/main/nopcommerce48_default_db.sql -O "$TMP_SQL"
sudo -u postgres PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h localhost -f "$TMP_SQL"
rm -f "$TMP_SQL"

sudo -u postgres PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "UPDATE \"Store\" SET \"Url\" = 'https://$DOMAIN/' WHERE \"Id\" = 1;"
sudo -u postgres PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "UPDATE \"Customer\" SET \"Username\" = '$ADMIN_EMAIL' WHERE \"Id\" = 1;"
sudo -u postgres PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "UPDATE \"Customer\" SET \"Email\" = '$ADMIN_EMAIL' WHERE \"Id\" = 1;"

if [[ -n "$ADMIN_PASS_HASH" ]]; then
  sudo -u postgres PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "UPDATE \"CustomerPassword\" SET \"Password\" = '$ADMIN_PASS_HASH' WHERE \"Id\" = 1;"
fi

if [[ -n "$ADMIN_SALT" ]]; then
  sudo -u postgres PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h localhost -c "UPDATE \"CustomerPassword\" SET \"PasswordSalt\" = '$ADMIN_SALT' WHERE \"Id\" = 1;"
fi

sudo systemctl restart "nopCommerce-$DOMAIN.service"
sudo systemctl reload nginx

echo "DONE: https://$DOMAIN"
REMOTE

sudo bash /tmp/nop_provision.sh "$DOMAIN" "$DB_NAME" "$DB_USER" "$DB_PASS" "$ADMIN_EMAIL" "$ADMIN_PASS_HASH" "$ADMIN_SALT"
rm -f /tmp/nop_provision.sh
