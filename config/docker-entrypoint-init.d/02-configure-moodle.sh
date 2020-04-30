#!/bin/sh
#
# Moodle configuration script
#
set -eo pipefail

# Check that the database is available
echo "Waiting for $database:$port to be ready"
while ! nc -w 1 $DB_HOST $DB_PORT; do
    # Show some progress
    echo -n '.';
    sleep 1;
done
echo "$database is ready"
# Give it another 3 seconds.
sleep 3;


# Check if the config.php file exists
if [ ! -f /var/www/html/config.php ]; then

    echo "Generating config.php file..."
    php /var/www/html/admin/cli/install.php \
        --lang=$MOODLE_LANGUAGE \
        --wwwroot=$SITE_URL\
        --dataroot=/var/www/moodledata/ \
        --dbtype=$DB_TYPE \
        --dbhost=$DB_HOST \
        --dbname=$DB_NAME \
        --dbuser=$DB_USER \
        --dbpass=$DB_USER \
        --dbport=$DB_PORT \
        --prefix=$DB_PREFIX \
        --fullname=Dockerized_Moodle \
        --shortname=moodle \
        --adminuser=$MOODLE_USERNAME \
        --adminpass=$MOODLE_PASSWORD \
        --adminemail=$MOODLE_EMAIL \
        --non-interactive \
        --agree-license \
        --skip-database

    if [ "$SSLPROXY" = 'true' ]; then
        sed -i '/require_once/i $CFG->sslproxy=true;' /var/www/html/config.php
    fi

fi

# Check if the database is already installed
if php /var/www/html/admin/cli/isinstalled.php ; then

    echo "Installing database..."
    php /var/www/html/admin/cli/install_database.php \
        --lang=$MOODLE_LANGUAGE \
        --adminuser=$MOODLE_USERNAME \
        --adminpass=$MOODLE_PASSWORD \
        --adminemail=$MOODLE_EMAIL \
        --fullname=Dockerized_Moodle \
        --shortname=moodle \
        --agree-license

    echo "Configuring settings..."
    # php /var/www/html/admin/cli/cfg.php --name=slasharguments --set=0
    php /var/www/html/admin/cli/cfg.php --name=pathtophp --set=/usr/bin/php
    php /var/www/html/admin/cli/cfg.php --name=pathtodu --set=/usr/bin/du
    # php /var/www/html/admin/cli/cfg.php --name=aspellpath --set=/usr/bin/aspell
    # php /var/www/html/admin/cli/cfg.php --name=pathtodot --set=/usr/bin/dot
    # php /var/www/html/admin/cli/cfg.php --name=pathtogs --set=/usr/bin/gs
    # php /var/www/html/admin/cli/cfg.php --name=pathtopython --set=/usr/bin/python3
    php /var/www/html/admin/cli/cfg.php --name=enableblogs --set=0


    php /var/www/html/admin/cli/cfg.php --name=smtphosts --set=$SMTP_HOST:$SMTP_PORT
    php /var/www/html/admin/cli/cfg.php --name=smtpuser --set=$SMTP_USER
    php /var/www/html/admin/cli/cfg.php --name=smtppass --set=$SMTP_PASSWORD
    php /var/www/html/admin/cli/cfg.php --name=smtpsecure --set=$SMTP_PROTOCOL
    php /var/www/html/admin/cli/cfg.php --name=noreplyaddress --set=$MOODLE_MAIL_NOREPLY_ADDRESS
    php /var/www/html/admin/cli/cfg.php --name=emailsubjectprefix --set=$MOODLE_MAIL_PREFIX

else
    echo "Upgrading moodle..."
    php /var/www/html/admin/cli/maintenance.php --enable
    php /var/www/html/admin/cli/upgrade.php
    php /var/www/html/admin/cli/maintenance.php --disable
fi













