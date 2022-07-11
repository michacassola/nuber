#!/bin/bash
#
# Nuber.io
# Copyright 2020 - 2021 Jamiel Sharief
# 
# This script should be run inside a Ubuntu container
#
# To create: 
#  
# $ lxc launch ubuntu:20.04 nuber-app
# $ lxc exec nuber-app bash
# $ bash <(curl -s https://www.nuber.io/container-setup.sh)
#
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'

abort()
{
  echo "${RED}ERROR:${WHITE} $1"
  exit 1
}

okStatus()
{
  echo 
  echo -e "${WHITE}[${GREEN} OK ${WHITE}] $1"
  echo 
}

if [ "$EUID" -ne 0 ]; then
  abort "You must run this script as root or with sudo privledges."
fi


if ! apt-get update -y; then
  abort "Error updating the system, not internet access"
fi

apt-get upgrade -y
apt-get install -y curl git nano unzip rsync zip apache2 libapache2-mod-php php php-apcu php-cli php-common php-curl php-intl php-json php-mailparse php-mbstring php-mysql php-opcache php-pear php-readline php-xml php-zip npm sqlite3 php-sqlite3 cron

curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

if [ ! -f /usr/local/bin/composer ]; then
    abort 'Unable to download Composer'
fi

# Upgrade nodejs 
npm cache clean -f
npm install -g n
n 14

okStatus 'Apache, PHP & NPM installed'

# Create SERVER Certificates
mkdir /etc/apache2/ssl
openssl req -x509 -sha256 -nodes -newkey rsa:4096 -days 3650 -keyout /etc/apache2/ssl/privateKey -out /etc/apache2/ssl/certificate -subj "/CN=localhost"  -extensions EXT -config <( \
   printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")

# Enable Modules proxy etc are needed if only using rewrite
a2enmod rewrite ssl proxy proxy_http proxy_wstunnel expires

okStatus 'Apache modules configured '

export COMPOSER_ALLOW_SUPERUSER=1

# Download Source Code
if [ "$1" != "--docker" ] 
then
  rm -rf /var/www
  mkdir /var/www
  cd /var/www
  
  git clone https://github.com/nuber-io/nuber .
  # Setup composer and app
  composer install --no-dev --no-interaction 
  bin/install
fi

# Switch to WWW
cd /var/www

VERSION=$(cat "version.txt"); 

# Setup File Perms - create cache directory before cron job does
chown -R www-data:www-data /var/www
chmod -R 0775 /var/www
chmod -R 0776 /var/www/tmp

# Configure the Database for the container
# Configure the Database
if [ "$1" != "--docker" ] 
then
  source config/.env
  bin/console db:setup
  bin/console db:migrate
fi

bin/console cache:clear

# Ensure permission goodness
if [ -f data/nuber.db ]; then
  chown www-data:www-data data/nuber.db
  chmod 600 data/nuber.db
fi

# Config apache
if [ "$1" = "--docker" ] 
then
  cp /var/www/config/apache-docker.conf /etc/apache2/sites-available/000-default.conf
else 
  cp /var/www/config/apache.conf /etc/apache2/sites-available/000-default.conf
  systemctl restart apache2
fi

# Install NodeJS dependencies
if [ "$1" != "--docker" ] 
then
  cd /var/www/websocket
  npm install
fi

# Enable PHP Extensions.
if [ "$1" = "--docker" ] 
then
  apt install php-dev php-xdebug
fi

# Setup CRON
# To enable in Docker run (needs an entry script to start automatically)
# $ service cron start
(echo "* * * * * cd /var/www && bin/console schedule:run") | crontab  -u www-data -

# Install Updater
if [ "$1" != "--docker" ] 
then
  cd /var/www
  vendor/bin/updater init --version ${VERSION}
fi

# download image list
bin/console image:list

okStatus 'Nuber installed';