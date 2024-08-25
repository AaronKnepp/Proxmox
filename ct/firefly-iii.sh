#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/AaronKnepp/Proxmox/firefly-iii/misc/build.func)
# Copyright (c) 2021-2024 
# Author: 
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
    _______           ______     
   / ____(_)_______  / __/ /_  __
  / /_  / / ___/ _ \/ /_/ / / / /
 / __/ / / /  /  __/ __/ / /_/ / 
/_/   /_/_/   \___/_/ /_/\__, /  
                        /____/   

EOF
}
header_info
echo -e "Loading..."
APP="firefly-iii"
var_disk="2"
var_cpu="1"
var_ram="512"
var_os="debian"
var_version="12"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

function update_script() {
header_info
if [[ ! -d /var/www/firefly-iii ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
php_version=$(php -v | head -n 1 | awk '{print $2}')
if [[ ! $php_version == "8.3"* ]]; then
  msg_info "Updating PHP"
  curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ bookworm main" >/etc/apt/sources.list.d/php.list
  apt-get update
  apt-get install -y php8.3 php8.3-cli php8.3-{bcmath,intl,curl,zip,gd,xml,mbstring,sqlite3}
  service apache2 restart
  apt autoremove
  msg_ok "Updated PHP"
fi
msg_info "Updating ${APP}"
# https://github.com/firefly-iii/docs/blob/5cb887f44a77d2b86ca84249139464d740b36e86/docs/docs/how-to/firefly-iii/upgrade/self-managed.md
# TODO: Download from githup, like install and validate integrity with hash
# TODO: Move the old directory, like an "*-old" mv
# Extract the zip, but don't overwrite the storage directory
# Firefly III's upgrade commands
cd /var/www/firefly-iii
php artisan migrate --seed
php artisan firefly-iii:decrypt-all
php artisan cache:clear
php artisan view:clear
php artisan firefly-iii:upgrade-database
php artisan firefly-iii:laravel-passport-keys
msg_ok "Updated Successfully"
exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}http://${IP}${CL} \n"
