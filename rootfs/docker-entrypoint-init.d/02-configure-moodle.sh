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

# Check that the database replica is available
if [ -n "$DB_HOST_REPLICA" ]; then
    if [ -n "$DB_PORT_REPLICA" ]; then
        echo "Waiting for $DB_HOST_REPLICA:$DB_PORT_REPLICA to be ready"
        while ! nc -w 1 "$DB_HOST_REPLICA" "$DB_PORT_REPLICA"; do
            # Show some progress
            echo -n '.';
            sleep 1;
        done
    else
        echo "Waiting for $DB_HOST_REPLICA:$DB_PORT to be ready"
        while ! nc -w 1 "$DB_HOST_REPLICA" "$DB_PORT"; do
            # Show some progress
            echo -n '.';
            sleep 1;
        done
    fi
    echo "$DB_HOST_REPLICA is ready"
fi
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
    ENV_VAR='var' php82 -d max_input_vars=10000 /var/www/html/admin/cli/install.php \
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

    # Set extra database settings
    if [ -n "$DB_FETCHBUFFERSIZE" ]; then
        sed -i "/\$CFG->dboptions/a \ \ "\''fetchbuffersize'\'" => $DB_FETCHBUFFERSIZE," /var/www/html/config.php
    fi
    if [ "$DB_DBHANDLEOPTIONS" = 'true' ]; then
        sed -i "/\$CFG->dboptions/a \ \ "\''dbhandlesoptions'\'" => true," /var/www/html/config.php
    fi
    if [ -n "$DB_HOST_REPLICA" ]; then
        if [ -n "$DB_USER_REPLICA" ] && [ -n "$DB_PASS_REPLICA" ] && [ -n "$DB_PORT_REPLICA" ]; then
            sed -i "/\$CFG->dboptions/a \ \ "\''readonly'\'" => [ \'instance\' => [ \'dbhost\' => \'$DB_HOST_REPLICA\', \'dbport\' => \'$DB_PORT_REPLICA\', \'dbuser\' => \'$DB_USER_REPLICA\', \'dbpass\' => \'$DB_PASS_REPLICA\' ] ]," /var/www/html/config.php
        else
            sed -i "/\$CFG->dboptions/a \ \ "\''readonly'\'" => [ \'instance\' => [ \'$DB_HOST_REPLICA\' ] ]," /var/www/html/config.php
        fi
    fi

    if [ "$SSLPROXY" = 'true' ]; then
        sed -i '/require_once/i $CFG->sslproxy=true;' /var/www/html/config.php
    fi

    # Avoid allowing executable paths to be set via the Admin GUI
    echo "\$CFG->preventexecpath = true;" >> /var/www/html/config.php

fi

# Check if the database is already installed
if php82 -d max_input_vars=10000 /var/www/html/admin/cli/isinstalled.php ; then

    echo "Installing database..."
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/install_database.php \
        --lang=$MOODLE_LANGUAGE \
        --adminuser=$MOODLE_USERNAME \
        --adminpass=$MOODLE_PASSWORD \
        --adminemail=$MOODLE_EMAIL \
        --fullname=Dockerized_Moodle \
        --shortname=moodle \
        --agree-license

    echo "Configuring settings..."

    # php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=slasharguments --set=0
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtophp --set=/usr/bin/php82
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtodu --set=/usr/bin/du
    # php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=aspellpath --set=/usr/bin/aspell
    # php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtodot --set=/usr/bin/dot
    # php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtogs --set=/usr/bin/gs
    # php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtopython --set=/usr/bin/python3
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=enableblogs --set=0


    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtphosts --set=$SMTP_HOST:$SMTP_PORT
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtpuser --set=$SMTP_USER
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtppass --set=$SMTP_PASSWORD
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtpsecure --set=$SMTP_PROTOCOL
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=noreplyaddress --set=$MOODLE_MAIL_NOREPLY_ADDRESS
    php82 -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=emailsubjectprefix --set=$MOODLE_MAIL_PREFIX
    
    # Remove .swf (flash) plugin for security reasons DISABLED BECAUSE IS REQUIRED
    #php82 -d max_input_vars=10000 /var/www/html/admin/cli/uninstall_plugins.php --plugins=media_swf --run

    # Avoid writing the config file
    chmod 444 config.php

    # Fix publicpaths check to point to the internal container on port 8080
    sed -i 's/wwwroot/wwwroot\ \. \"\:8080\"/g' lib/classes/check/environment/publicpaths.php

else
    if [ -z "$AUTO_UPDATE_MOODLE" ] || [ "$AUTO_UPDATE_MOODLE" = true ]; then
        echo "Upgrading moodle..."
        php82 -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --enable
        php82 -d max_input_vars=10000 /var/www/html/admin/cli/upgrade.php --non-interactive --allow-unstable
        php82 -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --disable
    else
        echo "Skipped auto update of Moodle"
    fi
fi
