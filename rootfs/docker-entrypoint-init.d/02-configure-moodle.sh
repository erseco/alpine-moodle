#!/bin/sh
#
# Moodle configuration script
#
set -eo pipefail

# Check that the database is available
echo "Waiting for database to be ready..."
while ! nc -w 1 $DB_HOST $DB_PORT; do
    # Show some progress
    echo -n '.';
    sleep 1;
done
echo -e "\n\nGreat, "$DB_HOST" is ready!"
# Give it another 3 seconds.
sleep 3;

#Add trusted certificates to "ldap-truststore"
if [ "$MY_CERTIFICATES" != 'none' ]; then
    echo "Adding certificates to truststore..."
    echo "$MY_CERTIFICATES" | base64 -d > /etc/openldap/my-certificates/extra.pem
fi

# Check if the config.php file exists
if [ ! -f /var/www/html/config.php ]; then

    echo "Generating config.php file..."
    ENV_VAR='var' php81 -d max_input_vars=10000 /var/www/html/admin/cli/install.php \
        --lang=$MOODLE_LANGUAGE \
        --wwwroot=$SITE_URL \
        --dataroot=/var/www/moodledata/ \
        --dbtype=$DB_TYPE \
        --dbhost=$DB_HOST \
        --dbname=$DB_NAME \
        --dbuser=$DB_USER \
        --dbpass=$DB_PASS \
        --dbport=$DB_PORT \
        --prefix=$DB_PREFIX \
        --fullname=Dockerized_Moodle \
        --shortname=moodle \
        --adminuser=$MOODLE_USERNAME \
        --adminpass=$MOODLE_PASSWORD \
        --adminemail=$MOODLE_EMAIL \
        --non-interactive \
        --agree-license \
        --skip-database \
        --allow-unstable

    if [ "$SSLPROXY" = 'true' ]; then
        sed -i '/require_once/i $CFG->sslproxy=true;' /var/www/html/config.php
    fi

    # Avoid allowing executable paths to be set via the Admin GUI
    echo "\$CFG->preventexecpath = true;" >> /var/www/html/config.php

fi

# Check if the database is already installed
if php81 -d max_input_vars=10000 /var/www/html/admin/cli/isinstalled.php ; then

    echo "Installing database..."
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/install_database.php \
        --lang=$MOODLE_LANGUAGE \
        --adminuser=$MOODLE_USERNAME \
        --adminpass=$MOODLE_PASSWORD \
        --adminemail=$MOODLE_EMAIL \
        --fullname=Dockerized_Moodle \
        --shortname=moodle \
        --agree-license

    echo "Configuring settings..."

    # php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=slasharguments --set=0
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtophp --set=/usr/bin/php81
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtodu --set=/usr/bin/du
    # php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=aspellpath --set=/usr/bin/aspell
    # php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtodot --set=/usr/bin/dot
    # php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtogs --set=/usr/bin/gs
    # php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtopython --set=/usr/bin/python3
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=enableblogs --set=0


    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtphosts --set=$SMTP_HOST:$SMTP_PORT
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtpuser --set=$SMTP_USER
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtppass --set=$SMTP_PASSWORD
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtpsecure --set=$SMTP_PROTOCOL
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=noreplyaddress --set=$MOODLE_MAIL_NOREPLY_ADDRESS
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=emailsubjectprefix --set=$MOODLE_MAIL_PREFIX
    
    # Remove .swf (flash) plugin for security reasons DISABLED BECAUSE IS REQUIRED
    #php81 -d max_input_vars=10000 /var/www/html/admin/cli/uninstall_plugins.php --plugins=media_swf --run

    # Avoid writing the config file
    chmod 444 config.php

    # Fix publicpaths check to point to the internal container on port 8080
    sed -i 's/wwwroot/wwwroot\ \. \"\:8080\"/g' lib/classes/check/environment/publicpaths.php

else
    echo "Upgrading moodle..."
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --enable
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/upgrade.php --non-interactive --allow-unstable
    php81 -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --disable
fi
