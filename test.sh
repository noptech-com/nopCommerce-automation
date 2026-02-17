#!/bin/bash

YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$1" ]; then
   echo -e "${RED}Missing: PostgreSQL database user or other argument!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-user database-password domain-name nopVersion dbType [nopCommerceEmail] [nopCommercePassword] [nopCommercePasswordSalt] [limitedUser] [limitedUserPassword]\n${NC}";
   exit 1
fi

if [ -z "$2" ]; then
   echo -e "${RED}Missing: PostgreSQL database password or other argument!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-user database-password domain-name nopVersion dbType [nopCommerceEmail] [nopCommercePassword] [nopCommercePasswordSalt] [limitedUser] [limitedUserPassword]\n${NC}";
   exit 1
fi

if [ -z "$3" ]; then
   echo -e "${RED}Missing: domain name or other argument!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-user database-password domain-name nopVersion dbType [nopCommerceEmail] [nopCommercePassword] [nopCommercePasswordSalt] [limitedUser] [limitedUserPassword]\n${NC}";
   exit 1
fi

if [ -z "$4" ]; then
   echo -e "${RED}Missing: nopCommerce version (4.6/4.7/4.8/4.9)!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-user database-password domain-name nopVersion dbType [nopCommerceEmail] [nopCommercePassword] [nopCommercePasswordSalt] [limitedUser] [limitedUserPassword]\n${NC}";
   exit 1
fi

if [ -z "$5" ]; then
   echo -e "${RED}Missing: database type (postgres/mssql/mysql)!\n${NC}";
   echo -e "${YELLOW}Format to use: ./$(basename "$0") database-user database-password domain-name nopVersion dbType [nopCommerceEmail] [nopCommercePassword] [nopCommercePasswordSalt] [limitedUser] [limitedUserPassword]\n${NC}";
   exit 1
fi

database_user=$1
database_password=$2
domain_name=$3
nop_version=$4
db_type=$5
RELEASE_VERSION=$(grep VERSION_ID /etc/os-release | cut -d '"' -f2)
# Името на базата = първата част от домейна (преди точката), напр. zetys8ic4tLE за zetys8ic4tLE.nop-tech.com
database_name=$(echo "$domain_name" | cut -d. -f1)

nopCommerceEmail=$6
nopCommercePassword=$7
nopCommercePasswordSalt=$8

# Опционален ограничен потребител за достъп само до файловете на nopCommerce
limited_user=$9
limited_user_password=${10}

echo -e "${YELLOW}[1/8] Параметри и версия:${NC}"
echo "  Database: $database_name"
echo "  User: $database_user"
echo "  Domain: $domain_name"
echo "  Email: $nopCommerceEmail"
echo "  nopCommerce version: $nop_version"
echo "  DB type: $db_type"

# Определяне на правилната .NET версия и nopCommerce пакет според nop_version
case "$nop_version" in
  "4.6")
    dotnet_runtime_pkg="aspnetcore-runtime-7.0"
    nop_zip_url="https://github.com/nopSolutions/nopCommerce/releases/download/release-4.60.6/nopCommerce_4.60.6_NoSource_linux_x64.zip"
    nop_zip_dir="nopCommerce_4.60.6_NoSource_linux_x64"
    db_version_tag="46"
    ;;
  "4.7")
    dotnet_runtime_pkg="aspnetcore-runtime-8.0"
    nop_zip_url="https://github.com/nopSolutions/nopCommerce/releases/download/release-4.70.5/nopCommerce_4.70.5_NoSource_linux_x64.zip"
    nop_zip_dir="nopCommerce_4.70.5_NoSource_linux_x64"
    db_version_tag="47"
    ;;
  "4.8")
    dotnet_runtime_pkg="aspnetcore-runtime-9.0"
    nop_zip_url="https://github.com/nopSolutions/nopCommerce/releases/download/release-4.80.9/nopCommerce_4.80.9_NoSource_linux_x64.zip"
    nop_zip_dir="nopCommerce_4.80.9_NoSource_linux_x64"
    db_version_tag="48"
    ;;
  "4.9")
    dotnet_runtime_pkg="aspnetcore-runtime-9.0"
    nop_zip_url="https://github.com/nopSolutions/nopCommerce/releases/download/release-4.90.3/nopCommerce_4.90.3_NoSource_linux_x64.zip"
    nop_zip_dir="nopCommerce_4.90.3_NoSource_linux_x64"
    db_version_tag="49"
    ;;
  *)
    echo -e "${RED}Unsupported nopCommerce version: $nop_version. Use 4.6, 4.7, 4.8, or 4.9.${NC}"
    exit 1
    ;;
esac

# Тип база данни: postgres / mssql / mysql
case "$db_type" in
  "postgres")
    data_provider="postgresql"
    connection_string="Server=localhost;Database=$database_name;User Id=$database_user;Password=$database_password"
    db_sql_file="nopcommerce${db_version_tag}_postgres_default_db.sql"
    ;;
  "mssql")
    data_provider="sqlserver"
    connection_string="Server=localhost;Database=$database_name;User Id=$database_user;Password=$database_password;Encrypt=True;TrustServerCertificate=True"
    db_sql_file="nopcommerce${db_version_tag}_mssql_default_db.sql"
    ;;
  "mysql")
    data_provider="mysql"
    connection_string="Server=localhost;Database=$database_name;Uid=$database_user;Pwd=$database_password"
    db_sql_file="nopcommerce${db_version_tag}_mysql_default_db.sql"
    ;;
  *)
    echo -e "${RED}Unsupported database type: $db_type. Use postgres, mssql, or mysql.${NC}"
    exit 1
    ;;
esac

db_sql_url="https://raw.githubusercontent.com/noptech-com/nopCommerce-automation/refs/heads/main/$db_sql_file"

echo -e "${YELLOW}[2/8] Инсталиране на .NET runtime ($dotnet_runtime_pkg) и зависимости...${NC}"

wget https://packages.microsoft.com/config/ubuntu/$RELEASE_VERSION/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo dpkg -i packages-microsoft-prod.deb
export DEBIAN_FRONTEND=noninteractive
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo apt-get update
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https "$dotnet_runtime_pkg"
echo "postfix postfix/main_mailer_type select Internet Site" | sudo -s debconf-set-selections
echo "postfix postfix/mailname string $(hostname --fqdn)" | sudo -s debconf-set-selections
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mailutils
IP=$(curl -4 -s ifconfig.me)
useradd -m -r -d /home/genius -s /bin/bash genius
echo 'genius:P@ssw0rd' | sudo chpasswd
echo "genius ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
sudo DEBIAN_FRONTEND=noninteractive apt purge --auto-remove -y mailutils postfix
sudo apt clean

while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 1; done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libgdiplus

echo -e "${YELLOW}[3/8] Инсталиране и базова конфигурация на nginx + SSL...${NC}"

nopcommerce_directory="/var/www/$domain_name"

sudo apt update
sudo apt install -y nginx

# Начална nginx конфигурация (само port 80) - нужна за certbot challenge
sudo tee /etc/nginx/sites-available/$domain_name <<EOF
server {
    listen 80;
    server_name $domain_name www.$domain_name;

    location / {
        proxy_pass http://localhost:5001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$domain_name /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

mkdir $nopcommerce_directory
sudo apt install -y certbot python3-certbot-nginx

# SSL е задължителен - certbot трябва да успее (основен домейн + www)
echo -e "${YELLOW}Получаване на SSL сертификат за $domain_name и www.$domain_name...${NC}"

# Използваме certonly (не пипа nginx конфигурацията, ние я настройваме ръчно по-долу)
if ! sudo certbot certonly --nginx -d $domain_name -d www.$domain_name --agree-tos --no-eff-email -m office@nop-tech.com --non-interactive; then
    echo -e "${RED}ГРЕШКА: Certbot не успя да получи SSL сертификат!${NC}"
    echo -e "${YELLOW}Проверете: DNS A запис за $domain_name -> $IP и порт 80 е отворен${NC}"
    exit 1
fi

SSL_CERT_PATH="/etc/letsencrypt/live/$domain_name/fullchain.pem"
if [ ! -f "$SSL_CERT_PATH" ]; then
    echo -e "${RED}ГРЕШКА: SSL сертификатът не е създаден.${NC}"
    exit 1
fi
USE_SSL=true

NGINX_CONFIG="/etc/nginx/sites-available/$domain_name"

# Пълна nginx конфигурация с SSL - основен домейн + www (www винаги се пренасочва към без www)
sudo tee "$NGINX_CONFIG" <<EOF
# HTTPS server for main domain
server {
    listen 443 ssl http2;
    server_name $domain_name;

    client_max_body_size 250M;

    ssl_certificate /etc/letsencrypt/live/$domain_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain_name/privkey.pem;
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

# HTTPS www -> redirect to main (SSL cert включва и www)
server {
    listen 443 ssl http2;
    server_name www.$domain_name;

    ssl_certificate /etc/letsencrypt/live/$domain_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain_name/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    return 301 https://$domain_name\$request_uri;
}

# HTTP www -> redirect to main
server {
    listen 80;
    server_name www.$domain_name;

    return 301 https://$domain_name\$request_uri;
}

# HTTP to HTTPS redirect for base domain
server {
    listen 80;
    server_name $domain_name;

    return 301 https://$domain_name\$request_uri;
}
EOF

# IP redirect - само ако IP е получен (избягва server_name празен)
if [ -n "$IP" ] && [ "$IP" != "localhost" ]; then
    sudo tee -a "$NGINX_CONFIG" <<EOF

# Redirect direct IP access to domain
server {
    listen 80;
    server_name $IP;
    return 301 https://$domain_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $IP;

    ssl_certificate /etc/letsencrypt/live/$domain_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain_name/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    return 301 https://$domain_name\$request_uri;
}
EOF
fi

echo -e "${YELLOW}[4/8] Тестване и рестарт на nginx...${NC}"

if ! sudo nginx -t 2>/dev/null; then
    # Fallback за по-стари nginx: http2 on не се поддържа, използваме listen 443 ssl http2
    if grep -q "http2 on" "$NGINX_CONFIG" 2>/dev/null; then
        echo -e "${YELLOW}Опит с listen 443 ssl http2 за по-стари nginx...${NC}"
        sudo sed -i 's/listen 443 ssl;/listen 443 ssl http2;/' "$NGINX_CONFIG"
        sudo sed -i '/http2 on;/d' "$NGINX_CONFIG"
        if sudo nginx -t 2>/dev/null; then
            sudo systemctl restart nginx
        else
            echo -e "${YELLOW}Nginx конфигурацията има грешки. Проверете с: sudo nginx -t${NC}"
        fi
    else
        echo -e "${YELLOW}Nginx конфигурацията има грешки. Проверете с: sudo nginx -t${NC}"
    fi
else
    sudo systemctl restart nginx
fi

echo -e "${YELLOW}[5/8] Инсталация и подготовка на база данни ($db_type)...${NC}"

if [ "$db_type" = "postgres" ]; then
  sudo apt install -y postgresql postgresql-contrib

  # PostgreSQL: идентификатори с точки/тирета трябва да са в кавички
  DB_QUOTED="\"$database_name\""
  USER_QUOTED="\"$database_user\""

  sudo -u postgres psql -c "CREATE USER $USER_QUOTED WITH PASSWORD '$database_password';"
  sudo -u postgres psql -c "CREATE DATABASE $DB_QUOTED WITH OWNER $USER_QUOTED;"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_QUOTED TO $USER_QUOTED;"
  sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS citext; CREATE EXTENSION IF NOT EXISTS pgcrypto;" -d "$database_name"
  sudo -u postgres psql -c "ALTER USER $USER_QUOTED WITH SUPERUSER;"
elif [ "$db_type" = "mysql" ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
  sudo systemctl enable mysql
  sudo systemctl start mysql

  # Създаваме база и потребител за MySQL
  sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`$database_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  sudo mysql -e "CREATE USER IF NOT EXISTS '$database_user'@'localhost' IDENTIFIED BY '$database_password';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON \`$database_name\`.* TO '$database_user'@'localhost';"
  sudo mysql -e "FLUSH PRIVILEGES;"
elif [ "$db_type" = "mssql" ]; then
  echo -e "${YELLOW}  [MSSQL] Инсталиране и настройка на SQL Server (Express) за MSSQL база...${NC}"

  MSSQL_SA_PASSWORD="$database_password"
  MSSQL_PID="Express"

  curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc >/dev/null

  # Инсталираме инструментите sqlcmd (пълният път се ползва по-долу)
  if [ ! -x /opt/mssql-tools/bin/sqlcmd ]; then
    echo -e "${YELLOW}  [MSSQL] Инсталиране на mssql-tools (sqlcmd)...${NC}"
    curl https://packages.microsoft.com/config/ubuntu/$RELEASE_VERSION/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list >/dev/null
    while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do echo -e "${YELLOW}  [MSSQL] Изчакване dpkg lock...${NC}"; sleep 5; done
    sudo apt-get update
    while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do echo -e "${YELLOW}  [MSSQL] Изчакване dpkg lock...${NC}"; sleep 5; done
    sudo ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev
    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' | sudo tee /etc/profile.d/mssql-tools.sh >/dev/null
  fi

  # Инсталираме SQL Server само ако още не е наличен
  if ! systemctl status mssql-server >/dev/null 2>&1; then
    echo -e "${YELLOW}  [MSSQL] Инсталиране на mssql-server...${NC}"
    curl https://packages.microsoft.com/config/ubuntu/$RELEASE_VERSION/mssql-server-2019.list | sudo tee /etc/apt/sources.list.d/mssql-server-2019.list >/dev/null
    while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do echo -e "${YELLOW}  [MSSQL] Изчакване освобождаване на dpkg lock...${NC}"; sleep 5; done
    sudo apt-get update
    while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do echo -e "${YELLOW}  [MSSQL] Изчакване освобождаване на dpkg lock...${NC}"; sleep 5; done
    echo -e "${YELLOW}  [MSSQL] Сваляне и инсталиране на mssql-server (може 5–15 мин, изчакайте)...${NC}"
    sudo apt-get install -y mssql-server
    echo -e "${YELLOW}  [MSSQL] Конфигуриране на SQL Server (mssql-conf setup)...${NC}"
    sudo systemctl stop mssql-server 2>/dev/null || true
    sudo chown -R mssql:mssql /var/opt/mssql
    sudo chmod 700 /var/opt/mssql/data 2>/dev/null || true
    if ! sudo MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" MSSQL_PID="$MSSQL_PID" /opt/mssql/bin/mssql-conf -n setup accept-eula; then
      echo -e "${RED}  [MSSQL] mssql-conf setup е неуспешен. Проверете /var/opt/mssql/log/errorlog${NC}"
      exit 1
    fi
    echo -e "${YELLOW}  [MSSQL] Конфигурацията приключи. Стартиране на услугата...${NC}"
    sudo systemctl enable mssql-server

    # Check if DBMS is running and accepts connections (If it accepts connections, then we can stop in gracefully)
    # We make up to 10 attempts which is more then enough for mssql-server to boot
    for i in {1..10}; do
        /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "SQL Server is UP and Ready!"
            break
        fi
        echo -n "."
        sleep 1
    done

    sudo systemctl restart mssql-server
  fi


  # Изчакваме SQL Server да стартира (до ~2 мин)
  echo -e "${YELLOW}  [MSSQL] Изчакване SQL Server да приема връзки...${NC}"
  COUNTER=1
  ERRSTATUS=1
  while [ $COUNTER -le 24 ] && [ $ERRSTATUS -ne 0 ]; do
    echo -e "${YELLOW}  [MSSQL] Опит $COUNTER/24...${NC}"
    sleep 5
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" >/dev/null 2>&1
    ERRSTATUS=$?
    COUNTER=$((COUNTER+1))
  done

  if [ $ERRSTATUS -ne 0 ]; then
    echo -e "${RED}  [MSSQL] Неуспешно свързване към локалния SQL Server след 24 опита. Проверете паролата (SA policy) и /var/opt/mssql/log/errorlog${NC}"
    exit 1
  fi
  echo -e "${YELLOW}  [MSSQL] SQL Server е на линия. Продължаваме с базата...${NC}"

  # Създаваме login, база и db_owner потребител за nopCommerce
  echo -e "${YELLOW}  [MSSQL] Създаване на login, база и db_owner потребител...${NC}"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'$database_user') CREATE LOGIN [$database_user] WITH PASSWORD = N'$database_password';"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "IF DB_ID(N'$database_name') IS NULL CREATE DATABASE [$database_name];"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d "$database_name" -Q "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$database_user') CREATE USER [$database_user] FOR LOGIN [$database_user]; ALTER ROLE [db_owner] ADD MEMBER [$database_user];"
fi

echo -e "${YELLOW}[6/8] Сваляне и разархивиране на nopCommerce...${NC}"

cd $nopcommerce_directory
wget "$nop_zip_url" -O nopCommerce.zip
apt-get install -y unzip
unzip -o -qq nopCommerce.zip

# nopCommerce zip създава подпапка - преместваме файловете в корена
if [ -d "$nop_zip_dir" ]; then
    mv "$nop_zip_dir"/* . 2>/dev/null || true
    mv "$nop_zip_dir"/.[!.]* . 2>/dev/null || true
    rmdir "$nop_zip_dir" 2>/dev/null || true
fi

mkdir -p bin logs
cd ..
chgrp -R www-data $nopcommerce_directory
chown -R www-data $nopcommerce_directory

echo -e "${YELLOW}[7/8] Настройка на ограничен потребител (ако е подаден)...${NC}"

# Ако е подаден ограничен потребител, го заключваме само в nopCommerce директорията (chroot + SFTP)
if [ -n "$limited_user" ] && [ -n "$limited_user_password" ]; then
    echo -e "${YELLOW}Създаване на ограничен потребител $limited_user за достъп до $nopcommerce_directory...${NC}"
    if ! id "$limited_user" >/dev/null 2>&1; then
        sudo useradd -m -s /bin/bash "$limited_user"
    fi
    echo "$limited_user:$limited_user_password" | sudo chpasswd

    # Специална група само за този сайт
    limited_group="nop_$domain_name"
    sudo groupadd -f "$limited_group"

    # Добавяме www-data и ограничения потребител в групата
    sudo usermod -a -G "$limited_group" www-data
    sudo usermod -a -G "$limited_group" "$limited_user"

    # Chroot директорията трябва да е root:root и не‑writable за група/others
    sudo chown root:root "$nopcommerce_directory"
    sudo chmod 755 "$nopcommerce_directory"

    # Съдържанието вътре – достъпно за www-data и ограничения потребител чрез групата
    sudo chown -R www-data:"$limited_group" "$nopcommerce_directory"/*
    sudo find "$nopcommerce_directory" -mindepth 1 -type d -exec chmod 770 {} \;
    sudo find "$nopcommerce_directory" -mindepth 1 -type f -exec chmod 660 {} \;

    # Настройка на sshd за chroot + SFTP-only за този потребител
    if ! grep -q "Match User $limited_user" /etc/ssh/sshd_config; then
        sudo tee -a /etc/ssh/sshd_config <<EOF_SSH
Match User $limited_user
  ChrootDirectory $nopcommerce_directory
  ForceCommand internal-sftp
  X11Forwarding no
  AllowTcpForwarding no
EOF_SSH
        sudo systemctl reload sshd 2>/dev/null || sudo service ssh reload 2>/dev/null || true
    fi

    echo -e "${YELLOW}Потребител $limited_user е ограничен само до $nopcommerce_directory (SFTP, chroot).${NC}"
fi

echo -e "${YELLOW}[8/8] Създаване на systemd услуга за nopCommerce и финална конфигурация...${NC}"

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

for i in {1..10}; do
    if systemctl is-active --quiet "nopCommerce-${domain_name}.service"; then
      echo "nopCommerce-${domain_name} is running"
      sleep 1
      break
    else
        echo "Service is NOT running"
        systemctl status nopCommerce-${domain_name}.service
    fi
    echo -n "."
    sleep 1
done

systemctl restart nopCommerce-$domain_name.service

# Изчакваме услугата да е активна (running)
echo -e "${YELLOW}Изчакване на стартиране на nopCommerce услугата...${NC}"
for i in $(seq 1 30); do
  if [ "$(systemctl is-active nopCommerce-$domain_name.service 2>/dev/null)" = "active" ]; then
    echo -e "${YELLOW}nopCommerce услугата е активна.${NC}"
    break
  fi
  if [ $i -eq 30 ]; then
    echo -e "${RED}Грешка: nopCommerce услугата не стартира в рамките на 30 секунди.${NC}"
    systemctl status nopCommerce-$domain_name.service --no-pager
    exit 1
  fi
  sleep 1
done

# Изчакваме appsettings.json да се появи в App_Data (приложението го създава при първо стартиране)
APPSETTINGS="$nopcommerce_directory/App_Data/appsettings.json"
echo -e "${YELLOW}Изчакване на поява на appsettings.json в App_Data...${NC}"
for i in $(seq 1 45); do
  if [ -f "$APPSETTINGS" ]; then
    echo -e "${YELLOW}appsettings.json е намерен.${NC}"
    break
  fi
  if [ $i -eq 45 ]; then
    echo -e "${RED}Грешка: $APPSETTINGS не се появи след ~90 сек. Проверете логовете: journalctl -u nopCommerce-$domain_name.service${NC}"
    ls -la $nopcommerce_directory/
    ls -la $nopcommerce_directory/App_Data/ 2>/dev/null || true
    exit 1
  fi
  sleep 2
done

sed -i -z "s#\"ConnectionString\": \"\"#\"ConnectionString\": \"$connection_string\"#" "$APPSETTINGS"
sed -i "s/sqlserver/$data_provider/" "$APPSETTINGS"

sed -i '/"HostingConfig": {/,/}/c\
  "HostingConfig": {\
    "UseProxy": true,\
    "ForwardedProtoHeaderName": "X-Forwarded-Proto",\
    "ForwardedForHeaderName": "X-Forwarded-For",\
    "KnownProxies": null,\
    "KnownNetworks": null\
  },' "$APPSETTINGS"

wget "$db_sql_url" -O "$db_sql_file"
echo -e "${YELLOW}[DB] Импорт на default база и начални данни за $db_type...${NC}"

# The .sql files have Windows-like CRLF need to convert it into unix-like
# sudo apt update && sudo apt install dos2unix
# dos2unix "$db_sql_file"


if [ "$db_type" = "postgres" ]; then
  sudo -u postgres PGPASSWORD=$database_password psql -U "$database_user" -d "$database_name" -h localhost -f "$db_sql_file"
  sudo -u postgres PGPASSWORD=$database_password psql -U "$database_user" -d "$database_name" -h localhost -c "UPDATE \"Store\" SET \"Url\" = 'https://$domain_name/' WHERE \"Id\" = 1;"
  sudo -u postgres PGPASSWORD=$database_password psql -U "$database_user" -d "$database_name" -h localhost -c "UPDATE \"Customer\" SET \"Username\" = '$nopCommerceEmail' WHERE \"Id\" = 1;"
  sudo -u postgres PGPASSWORD=$database_password psql -U "$database_user" -d "$database_name" -h localhost -c "UPDATE \"Customer\" SET \"Email\" = '$nopCommerceEmail' WHERE \"Id\" = 1;"
  sudo -u postgres PGPASSWORD=$database_password psql -U "$database_user" -d "$database_name" -h localhost -c "UPDATE \"CustomerPassword\" SET \"Password\" = '$nopCommercePassword' WHERE \"Id\" = 1;"
  sudo -u postgres PGPASSWORD=$database_password psql -U "$database_user" -d "$database_name" -h localhost -c "UPDATE \"CustomerPassword\" SET \"PasswordSalt\" = '$nopCommercePasswordSalt' WHERE \"Id\" = 1;"
elif [ "$db_type" = "mysql" ]; then
  sudo mysql "$database_name" < "$db_sql_file"
  sudo mysql -e "UPDATE Store SET Url = 'https://$domain_name/' WHERE Id = 1;" "$database_name"
  sudo mysql -e "UPDATE Customer SET Username = '$nopCommerceEmail' WHERE Id = 1;" "$database_name"
  sudo mysql -e "UPDATE Customer SET Email = '$nopCommerceEmail' WHERE Id = 1;" "$database_name"
  sudo mysql -e "UPDATE CustomerPassword SET Password = '$nopCommercePassword' WHERE Id = 1;" "$database_name"
  sudo mysql -e "UPDATE CustomerPassword SET PasswordSalt = '$nopCommercePasswordSalt' WHERE Id = 1;" "$database_name"
elif [ "$db_type" = "mssql" ]; then
  # sed -E -i "s/\bdbo\b/${database_name}/g" "$db_sql_file"
  # sed -E -i "s/\bdbo_log\b/${database_name}_log/g" "$db_sql_file"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$database_password" -d "$database_name" -i "$db_sql_file"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$database_password" -d "$database_name" -Q "UPDATE [Store] SET [Url] = 'https://$domain_name/' WHERE [Id] = 1;"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$database_password" -d "$database_name" -Q "UPDATE [Customer] SET [Username] = '$nopCommerceEmail' WHERE [Id] = 1;"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$database_password" -d "$database_name" -Q "UPDATE [Customer] SET [Email] = '$nopCommerceEmail' WHERE [Id] = 1;"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$database_password" -d "$database_name" -Q "UPDATE [CustomerPassword] SET [Password] = '$nopCommercePassword' WHERE [Id] = 1;"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$database_password" -d "$database_name" -Q "UPDATE [CustomerPassword] SET [PasswordSalt] = '$nopCommercePasswordSalt' WHERE [Id] = 1;"
fi

rm "$db_sql_file"

systemctl restart nopCommerce-$domain_name.service
