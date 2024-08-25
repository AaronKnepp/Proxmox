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

msg_info "Installing firefly-iii"
#TODO: Adjust the grep and awk part of thisc ommand for reading the json
#  latest=$(curl -s https://version.firefly-iii.org/index.json | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
#  wget -q https://github.com/firefly-iii/firefly-iii/releases/download/v${latest}/FireflyIII-v${latest}.zip
wget -q https://github.com/firefly-iii/firefly-iii/releases/download/v6.1.16/FireflyIII-v6.1.16.zip
#TODO: Optional: checksum compareison from https://github.com/firefly-iii/firefly-iii/releases/download/v6.1.16/FireflyIII-v6.1.16.zip.sha256
$STD mkdir /var/www/firefly-iii
#TODO: Validate we don't need to do the www-data option that FF3 mentions
$STD unzip FireflyIII-v6.1.16.zip -d /var/www/firefly-iii
chown -R www-data:www-data /var/www/firefly-iii
sudo chmod -R 775 /var/www/firefly-iii/storage
#TODO: Configure apache2 to serve the FF3 page under the desired route. Otherwise it'll be firefly-iii/public
cp /var/www/firefly-iii/data-importer/.env.example .env
#TODO: Any other settings to config?
sed -i '/^DB_CONNECTION=/c\DB_CONNECTION=sqlite' /var/www/firefly-iii/data-importer/.env


#Init the database
touch /var/www/firefly-iii/storage/database/database.sqlite
php artisan firefly-iii:upgrade-database
php artisan firefly-iii:correct-database
php artisan firefly-iii:report-integrity
php artisan firefly-iii:laravel-passport-keys

cat <<EOF >/etc/apache2/sites-available/firefly-iii.conf
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/public
  ErrorLog /var/log/apache2/error.log
<Directory /var/www/public>
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
systemctl reload apache2
msg_ok "Installed firefly-iii"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
#rm -rf /root/FireflyIII-v${latest}.zip
rm -rf /root/FireflyIII-v6.1.16.zip
msg_ok "Cleaned"
