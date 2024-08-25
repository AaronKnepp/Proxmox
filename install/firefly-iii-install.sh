#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y mc
$STD apt-get install -y apt-transport-https
$STD apt-get install -y unzip
$STD apt-get install -y apache2
$STD apt-get install -y sqlite3
msg_ok "Installed Dependencies"

msg_info "Installing PHP8.3"
VERSION="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"
curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
echo -e "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $VERSION main" >/etc/apt/sources.list.d/php.list
$STD apt-get update
$STD apt-get install -y php8.3
$STD apt-get install -y php8.3-bcmath
$STD apt-get install -y php8.3-intl
$STD apt-get install -y php8.3-curl
$STD apt-get install -y php8.3-zip
$STD apt-get install -y php8.3-gd
$STD apt-get install -y php8.3-xml
$STD apt-get install -y php8.3-mbstring
$STD apt-get install -y php8.3-sqlite3
msg_ok "Installed PHP8.3"

latest=$(curl -s https://api.github.com/repos/firefly-iii/firefly-iii/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
msg_info "Installing firefly-iii ${latest}"
wget -q https://github.com/firefly-iii/firefly-iii/releases/download/${latest}/FireflyIII-${latest}.zip
# Verify file integrity
wget -q https://github.com/firefly-iii/firefly-iii/releases/download/${latest}/FireflyIII-${latest}.zip.sha256
sha256sum -c FireflyIII-${latest}.zip.sha256
mkdir /var/www/firefly-iii
$STD unzip FireflyIII-${latest} -d /var/www/firefly-iii

# Configure FF3
cd /var/www/firefly-iii
cp .env.example .env
# Generate own key for instance (Only on install!)
# Manually setting one to overwrite, to avoid the catch-22 of not having a key while trying to generate a key
#   See bug issue acknowledged: https://github.com/snipe/snipe-it/issues/13630
sed -i 's/^APP_KEY.*/APP_KEY=base64:hTUIUh9CP6dQx+6EjSlfWTgbaMaaRvlpEwk45vp+xmk=/' .env
php artisan key:generate --force --no-interaction &>/dev/null
# Use SQLite3 as the DB, dropping the other config lines for DB as SQLite doesn't use them
sed -i '/^DB_CONNECTION=/c\DB_CONNECTION=sqlite' .env
# Delete the other DB_ settings according to Firefly III's documentation (and confirmed errors if we don't delete)
sed -i '/^DB_.*[^DB_CONNECTION=sqlite]/d' .env
# Timezone configured to match server's
TIMEZONE="$(timedatectl show --va -p Timezone)"
sed -i "/^TZ=/c\TZ=${TIMEZONE}" .env
# User should still configure own site owner
read -r -p 'What site owner email would you like Firefly III to use?' siteowner
sed -i "/^SITE_OWNER=/c\SITE_OWNER=${siteowner}" .env

# Init the SQLite DB   https://docs.firefly-iii.org/references/faq/install/#i-want-to-use-sqlite
touch ./storage/database/database.sqlite
# Already in correct location to call artisan file from keygeneration, otherwise need "cd /var/www/firefly-iii"
#php artisan migrate --seed --force &>/dev/null
php artisan firefly-iii:upgrade-database &>/dev/null
php artisan firefly-iii:correct-database &>/dev/null
php artisan firefly-iii:report-integrity &>/dev/null
php artisan firefly-iii:laravel-passport-keys &>/dev/null

chown -R www-data:www-data /var/www/firefly-iii
chmod -R 777 /var/www/firefly-iii/storage

# Conf for Apache2 to FF3 public
cat <<EOF >/etc/apache2/sites-available/firefly-iii.conf
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/firefly-iii/public
  ErrorLog /var/log/apache2/error.log
<Directory /var/www>
  Options Indexes FollowSymLinks MultiViews
  AllowOverride All
  Order allow,deny
  allow from all
</Directory>
</VirtualHost>
EOF

$STD a2dissite 000-default.conf
$STD a2ensite firefly-iii.conf
$STD a2enmod php8.3
$STD a2enmod rewrite
service apache2 restart
msg_ok "Installed firefly-iii"

#TODO: Data Importer
read -r -p "Would you like to add the data importer? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  mkdir /var/www/firefly-iii-data-importer
  latest=$(curl -s https://api.github.com/repos/firefly-iii/data-importer/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
  msg_info "Installing firefly-iii Data Importer ${latest}"
  wget -q https://github.com/firefly-iii/data-importer/releases/download/${latest}/DataImporter-${latest}.zip
  # Verify file integrity
  wget -q https://github.com/firefly-iii/data-importer/releases/download/${latest}/DataImporter-${latest}.zip.sha256
  sha256sum -c DataImporter-${latest}.zip.sha256
  $STD unzip DataImporter-${latest} -d /var/www/firefly-iii-data-importer
  
  cd /var/www/firefly-iii-data-importer/
  cp .env.example .env
  sed -i "/^FIREFLY_III_URL=/c\FIREFLY_III=http://localhost" .env
  # Timezone configured to match server's
  sed -i "/^TZ=/c\TZ=${TIMEZONE}" .env
  sed -i 's|^\(APP_URL=http://localhost\)|\1/data-importer|' .env
 
  chown -R www-data:www-data /var/www/firefly-iii-data-importer
  chmod -R 777 /var/www/firefly-iii-data-importer/storage
  
  sed -i '/^Listen 80/a Listen 81' /etc/apache2/ports.conf
cat <<EOF >/etc/apache2/sites-available/firefly-iii-data-importer.conf
<VirtualHost *:81>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/firefly-iii-data-importer/public
  ErrorLog /var/log/apache2/error.log
<Directory /var/www>
  Options Indexes FollowSymLinks MultiViews
  AllowOverride All
  Order allow,deny
  allow from all
</Directory>
</VirtualHost>
EOF

  $STD a2ensite firefly-iii-data-importer.conf
  service apache2 restart

  rm -rf /root/DataImporter-${latest}.zip
  msg_ok "Installed firefly-iii Data Importer"
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
rm -rf /root/FireflyIII-${latest}.zip
msg_ok "Cleaned"
