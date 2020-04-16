#!/bin/bash

# Arguments
MYSQL_PASSWORD="${1}"
MYSQL_ROOT_PASSWORD="${2}"
SERVER_NAME="${3}"
ADMIN_USER="${4}"
ADMIN_PASSWORD="${5}"
NEXTCLOUD_VERSION="${6}"

## Add PHP repository
add-apt-repository ppa:ondrej/php
apt-get -y -q update

## Install packages
### Supresses password prompt
echo mysql-server-5.7 mysql-server/root_password password "$MYSQL_ROOT_PASSWORD" | debconf-set-selections
echo mysql-server-5.7 mysql-server/root_password_again password "$MYSQL_ROOT_PASSWORD" | debconf-set-selections
apt-get -y -q install git mysql-server-5.7 apache2 memcached php7.4 php7.4-gd php7.4-imagick php7.4-json php7.4-mysql php7.4-curl php7.4-mbstring php7.4-tokenizer php7.4-xml php7.4-intl php7.4-zip php7.4-apcu php7.4-memcached

# Install application
cd /var/www/nextcloud
git clone --no-checkout https://github.com/nextcloud/server --depth=1 --branch "$NEXTCLOUD_VERSION" tmp
mv tmp/.git .
rm -rf tmp
git reset --hard HEAD
git submodule update --init
chown -R www-data:www-data /var/www/nextcloud/

# Install phpunit
wget https://phar.phpunit.de/phpunit.phar
chmod +x phpunit.phar
mv phpunit.phar /usr/local/bin/phpunit

# Setup webserver
echo '
<VirtualHost *:80>
  # General
  ServerName '$SERVER_NAME'

  # Site
  DocumentRoot /var/www/nextcloud
  <Directory "/var/www/nextcloud">
    Require all granted
    Options +FollowSymlinks
    AllowOverride All

    <IfModule mod_dav.c>
      Dav off
    </IfModule>

    SetEnv HOME /var/www/nextcloud
    SetEnv HTTP_HOME /var/www/nextcloud
  </Directory>

  # Logs
  ErrorLog ${APACHE_LOG_DIR}/error.log
  CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
' > /etc/apache2/sites-available/000-default.conf
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

a2enmod headers
a2enmod env
a2enmod dir
a2enmod mime
a2dissite default-ssl

# Clean up virtual hosts
rm /etc/apache2/sites-available/default-ssl.conf

service apache2 restart

# Setup database
## Basic
sed -i "s/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf

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
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:system:set loglevel --value 0 --type integer
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:system:set trusted_domains 1 --value=192.168.50.12
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:system:set trusted_domains 2 --value="$SERVER_NAME"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ background:cron

## Add cronjob
echo '
# nextcloud
*/15  *  *  *  * /usr/bin/php -f /var/www/nextcloud/cron.php' > /var/spool/cron/crontabs/www-data

# Setup user_sql
cat /vagrant/init.sql | mysql -unextcloud -p"${MYSQL_PASSWORD}"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ app:enable user_sql
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.database" --value="nextcloud"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.driver" --value="mysql"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.hostname" --value="localhost"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.password" --value="${MYSQL_PASSWORD}"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.group" --value="sql_group"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.group.column.admin" --value="admin"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.group.column.gid" --value="gid"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.group.column.name" --value="name"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user" --value="sql_user"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.active" --value="active"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.disabled" --value="disabled"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.avatar" --value="provide_avatar"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.email" --value="email"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.home" --value="home"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.name" --value="display_name"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.password" --value="password"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.quota" --value="quota"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.salt" --value="salt"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.uid" --value="uid"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user.column.username" --value="username"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user_group" --value="sql_user_group"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user_group.column.gid" --value="gid"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.table.user_group.column.uid" --value="uid"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "db.username" --value="nextcloud"
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ config:app:set user_sql "opt.crypto_class" --value="OCA\\UserSQL\\Crypto\\Cleartext"
