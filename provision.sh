#!/bin/bash

# Arguments
MYSQL_PASSWORD=${1}
MYSQL_ROOT_PASSWORD=${2}
SERVER_NAME=${3}
ADMIN_USER=${4}
ADMIN_PASSWORD=${5}
NEXTCLOUD_VERSION=${6}

# Basics
apt-get -y -q update
apt-get -y -q upgrade
apt-get -y -q install build-essential

## Add PHP repository
add-apt-repository ppa:ondrej/php
apt-get -y -q update

## Install packages
### Supresses password prompt
echo mysql-server-5.7 mysql-server/root_password password $MYSQL_ROOT_PASSWORD | debconf-set-selections
echo mysql-server-5.7 mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD | debconf-set-selections
apt-get -y -q install git mysql-server-5.7 apache2 memcached php7.3 php7.3-gd php7.3-imagick php7.3-json php7.3-mysql php7.3-curl php7.3-mbstring php7.3-tokenizer php7.3-xml php7.3-intl php7.3-zip php7.3-apcu php7.3-memcached

# Install application
cd /var/www/nextcloud
git clone --no-checkout https://github.com/nextcloud/server tmp
mv tmp/.git .
rm -rf tmp
git checkout $NEXTCLOUD_VERSION
cd 3rdparty
git submodule update --init
chown -R www-data:www-data /var/www/nextcloud/

# Install phpunit
wget https://phar.phpunit.de/phpunit.phar
chmod +x phpunit.phar
mv phpunit.phar /usr/local/bin/phpunit

# Setup webserver
echo '
<VirtualHost *:80>
<IfModule mod_rewrite.c>
  RewriteEngine On

  # Force to SSL
  RewriteCond %{HTTPS} off
  RewriteRule ^(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]
</IfModule>
</VirtualHost>
<VirtualHost *:443>
<IfModule mod_ssl.c>
  # General
  ServerName '$SERVER_NAME'
  ServerAlias www.'$SERVER_NAME'

  SSLEngine on
  SSLCertificateFile      /etc/ssl/certs/apache-selfsigned.crt
  SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key

  # Site
  DocumentRoot /var/www/nextcloud
  <Directory "/var/www/nextcloud">
    Require all granted
    Options +FollowSymlinks
    AllowOverride All

    <IfModule mod_dav.c>
      Dav off
    </IfModule>

    <IfModule mod_headers.c>
      Header always set Strict-Transport-Security "max-age=63072000; includeSubdomains;"
    </IfModule>

    SetEnv HOME /var/www/nextcloud
    SetEnv HTTP_HOME /var/www/nextcloud
  </Directory>

  # Logs
  ErrorLog ${APACHE_LOG_DIR}/error.log
  CustomLog ${APACHE_LOG_DIR}/access.log combined
</IfModule>
</VirtualHost>
' > /etc/apache2/sites-available/000-default.conf
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -subj "/C=CO/ST=STATE/L=LOCATION/O=ORGANIZATION/CN=$SERVER_NAME"server -keyout /etc/ssl/private/apache-selfsigned.key -out /etc/ssl/certs/apache-selfsigned.crt

a2enmod ssl
a2enmod rewrite
a2enmod headers
a2enmod env
a2enmod dir
a2enmod mime
a2dissite default-ssl

sed -i 's/^\(;\)\(date\.timezone\s*=\).*$/\2 \"Europe\/Berlin\"/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(display_errors\s*=\).*$/\1 On/' /etc/php/7.3/apache2/php.ini

## Enable Opcache
sed -i 's/^\(;\)\(opcache\.validate_timestamps\s*=\).*$/\20/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(;\)\(opcache\.enable\s*=\).*$/\21/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(;\)\(opcache\.enable_cli\s*=\).*$/\21/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(;\)\(opcache\.interned_strings_buffer\s*=\).*$/\28/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(;\)\(opcache\.memory_consumption\s*=\).*$/\2128/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(;\)\(opcache\.max_accelerated_files\s*=\).*$/\210000/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(;\)\(opcache\.save_comments\s*=\).*$/\21/' /etc/php/7.3/apache2/php.ini
sed -i 's/^\(;\)\(opcache\.revalidate_freq\s*=\).*$/\21/' /etc/php/7.3/apache2/php.ini

# Clean up virtual hosts
rm /etc/apache2/sites-available/default-ssl.conf

service apache2 restart

# Setup database
## Basic
sed -i 's/^\(max_allowed_packet\s*=\s*\).*$/\1128M/' /etc/mysql/my.cnf
sed -i "s/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" /etc/mysql/my.cnf

echo '[client]
user = root
password = '$MYSQL_ROOT_PASSWORD'

[mysqladmin]
user = root
password = '$MYSQL_ROOT_PASSWORD > /home/vagrant/.my.cnf
cp /home/vagrant/.my.cnf /root/.my.cnf

service mysql restart

## Nextcloud
echo "CREATE DATABASE nextcloud;" | mysql -uroot
echo "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';" | mysql -uroot

# Configure Nextcloud
## Install application
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ maintenance:install --database=mysql --database-name=nextcloud --database-user=nextcloud --database-pass=$MYSQL_PASSWORD --admin-user=$ADMIN_USER --admin-pass=$ADMIN_PASSWORD

## Tweak config
sed -i '$i\ \ '\''memcache.local'\'' => '\''\\OC\\Memcache\\APCu'\'',' /var/www/nextcloud/config/config.php
sed -i '$i\ \ '\''memcache.distributed'\'' => '\''\\OC\\Memcache\\Memcached'\'',' /var/www/nextcloud/config/config.php
sed -i '$i\ \ '\''memcached_servers'\'' => array\(array\('\''localhost'\'', 11211\),\),' /var/www/nextcloud/config/config.php
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:system:set trusted_domains 1 --value=$SERVER_NAME
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ background:cron

## Add cronjob
echo '
# nextcloud
*/15  *  *  *  * /usr/bin/php -f /var/www/nextcloud/cron.php' > /var/spool/cron/crontabs/www-data
sudo -u www-data /usr/bin/php -f /var/www/nextcloud/cron.php

# Setup user_sql
cat /vagrant/init.sql | mysql -unextcloud -p"${MYSQL_PASSWORD}"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ app:enable user_sql
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.database" --value="nextcloud"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.driver" --value="mysql"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.hostname" --value="localhost"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.password" --value="${MYSQL_PASSWORD}"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.group" --value="sql_group"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.group.column.admin" --value="admin"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.group.column.gid" --value="name"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.group.column.name" --value="display_name"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user" --value="sql_user"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.active" --value="active"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.avatar" --value="provide_avatar"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.email" --value="email"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.home" --value="home"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.name" --value="display_name"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.password" --value="password"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.quota" --value="quota"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.salt" --value="salt"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.uid" --value="username"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user_group" --value="sql_user_group"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user_group.column.gid" --value="group_name"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user_group.column.uid" --value="username"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.username" --value="nextcloud"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "opt.crypto_class" --value="OCA\\UserSQL\\Crypto\\Cleartext"
