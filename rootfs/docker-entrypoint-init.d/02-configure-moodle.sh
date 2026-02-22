#!/bin/sh
#
# Moodle configuration script
#
set -eo pipefail

# Fail fast on invalid Redis auth configuration.
if [ -n "${REDIS_USER:-}" ] && [ -z "${REDIS_PASSWORD:-}" ]; then
    echo "ERROR: REDIS_USER requires REDIS_PASSWORD." >&2
    exit 1
fi

# Path to the config.php file
config_file="/var/www/html/config.php"

# Since Moodle 5.1, all web-accessible files are located inside the /public directory.
# MOODLE_PUBLIC_DIR is set to true if that directory exists, otherwise it is false (for older versions).
MOODLE_PUBLIC_DIR=false

# Function to update or add a configuration value
update_or_add_config_value() {
    local key="$1"  # The configuration key (e.g., $CFG->wwwroot)
    local value="$2"  # The new value for the configuration key

    if [ -z "$value" ]; then
        # If value is empty, remove the line with the key if it exists
        sed -i "/$key/d" "$config_file"
        return
    fi

    case "$value" in
        true|false|\[*)
            quote=''
            ;;
        *)
            quote="'"
            ;;
    esac

    if grep -q "$key" "$config_file"; then
        # If the key exists, replace its value
        sed -i "s|\($key\s*=\s*\)[^;]*;|\1$quote$value$quote;|g" "$config_file"

    else
        # If the key does not exist, add it before "require_once"
        sed -i "/require_once/i $key\t= $quote$value$quote;" "$config_file"

    fi
}

# Function to check the availability of a database
check_db_availability() {
    local db_host="$1"
    local db_port="$2"
    local db_name="$3"
    local db_user="$4"
    local db_pass="$5"

    echo "Waiting for $db_host:$db_port to be ready..."
    if [ "${DB_TYPE:-}" = "pgsql" ] && command -v php >/dev/null 2>&1; then
        while ! php -r '[$h,$p,$d,$u,$pw]=array_slice($argv,1,5); $cs="host={$h} port={$p} dbname={$d} user={$u} password={$pw} connect_timeout=1"; $c=@pg_connect($cs); if ($c) { pg_close($c); exit(0); } exit(1);' "$db_host" "$db_port" "$db_name" "$db_user" "$db_pass" >/dev/null 2>&1; do
            echo -n '.'
            sleep 1
        done
    else
        while ! nc -w 1 "$db_host" "$db_port" > /dev/null 2>&1; do
            echo -n '.'
            sleep 1
        done
    fi
    echo -e "\n\nGreat, $db_host is ready!"
}

# Function to generate config.php file
generate_config_file() {
    echo "Generating config.php file..."
    ENV_VAR='var' php -d max_input_vars=10000 /var/www/html/admin/cli/install.php \
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
        --fullname=$MOODLE_SITENAME \
        --shortname=moodle \
        --adminuser=$MOODLE_USERNAME \
        --adminpass=$MOODLE_PASSWORD \
        --adminemail=$MOODLE_EMAIL \
        --non-interactive \
        --agree-license \
        --skip-database \
        --allow-unstable
}

# Function to install the database
install_database() {
    echo "Installing database..."
    php -d max_input_vars=10000 /var/www/html/admin/cli/install_database.php \
        --lang=$MOODLE_LANGUAGE \
        --adminuser=$MOODLE_USERNAME \
        --adminpass=$MOODLE_PASSWORD \
        --adminemail=$MOODLE_EMAIL \
        --fullname=$MOODLE_SITENAME \
        --shortname=moodle \
        --agree-license
}

# Function to set extra database settings
set_extra_db_settings() {
    if [ -n "$DB_FETCHBUFFERSIZE" ]; then
        update_or_add_config_value "\$CFG->dboptions['fetchbuffersize']" "$DB_FETCHBUFFERSIZE"
    fi
    if [ "$DB_DBHANDLEOPTIONS" = 'true' ]; then
        update_or_add_config_value "\$CFG->dboptions['dbhandlesoptions']" 'true'
    fi
    if [ -n "$DB_HOST_REPLICA" ]; then
        if [ -n "$DB_USER_REPLICA" ] && [ -n "$DB_PASS_REPLICA" ] && [ -n "$DB_PORT_REPLICA" ]; then
            update_or_add_config_value "\$CFG->dboptions['readonly']" "[ 'instance' => [ 'dbhost' => '$DB_HOST_REPLICA', 'dbport' => '$DB_PORT_REPLICA', 'dbuser' => '$DB_USER_REPLICA', 'dbpass' => '$DB_PASS_REPLICA' ] ]"
        else
            update_or_add_config_value "\$CFG->dboptions['readonly']" "[ 'instance' => [ '$DB_HOST_REPLICA' ] ]"
        fi
    fi
}

# Function to upgrade config.php
upgrade_config_file() {
    echo "Upgrading config.php..."
    update_or_add_config_value "\$CFG->wwwroot" "$SITE_URL"
    update_or_add_config_value "\$CFG->dbtype" "$DB_TYPE"
    update_or_add_config_value "\$CFG->dbhost" "$DB_HOST"
    update_or_add_config_value "\$CFG->dbname" "$DB_NAME"
    update_or_add_config_value "\$CFG->dbuser" "$DB_USER"
    update_or_add_config_value "\$CFG->dbpass" "$DB_PASS"
    update_or_add_config_value "\$CFG->dbport" "$DB_PORT"
    update_or_add_config_value "\$CFG->prefix" "$DB_PREFIX"
    update_or_add_config_value "\$CFG->reverseproxy" "$REVERSEPROXY"
    update_or_add_config_value "\$CFG->sslproxy" "$SSLPROXY"
    update_or_add_config_value "\$CFG->preventexecpath" "true"

    # TODO: WIP for moodle 5.1dev
    update_or_add_config_value "\$CFG->enableanalytics" "false"

    # Configure Redis session settings safely (escaping-safe for any credentials).
    php -d max_input_vars=10000 /var/www/html/admin/cli/configure_redis_session.php "${REDIS_HOST:-}" "${REDIS_PASSWORD:-}" "${REDIS_USER:-}"

}

# Function to configure Moodle settings via CLI
configure_moodle_settings() {
    echo "Configuring settings..."
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtophp --set=/usr/bin/php
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtodu --set=/usr/bin/du
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=enableblogs --set=0
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtphosts --set="$SMTP_HOST:$SMTP_PORT"
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtpuser --set="$SMTP_USER"
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtppass --set="$SMTP_PASSWORD"
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=smtpsecure --set="$SMTP_PROTOCOL"
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=noreplyaddress --set="$MOODLE_MAIL_NOREPLY_ADDRESS"
    php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=emailsubjectprefix --set="$MOODLE_MAIL_PREFIX"

    # Added the binary path, but the executable can be not installed
    # php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=pathtopython --set="/usr/bin/python3"

    # Check if DEBUG is set to true
    if [ "${DEBUG:-false}" = "true" ]; then
        echo "Enabling debug mode..."
        php /var/www/html/admin/cli/cfg.php --name=debug --set=32767 # DEVELOPER
        php /var/www/html/admin/cli/cfg.php --name=debugdisplay --set=1
    else
        echo "Disabling debug mode..."
        php /var/www/html/admin/cli/cfg.php --name=debug --set=0 # NONE
        php /var/www/html/admin/cli/cfg.php --name=debugdisplay --set=0
    fi

}

# Function to perform some final configurations
final_configurations() {
    # Avoid writing the config file
    chmod 444 config.php

    # In Moodle versions prior to 5.1, the /public directory does not exist.
    # In these versions, we patch publicpaths.php to append ":8080" to the wwwroot check
    # in order to support running behind a custom port inside the container.
    if [ "$MOODLE_PUBLIC_DIR" = "false" ]; then
        sed -i 's/wwwroot/wwwroot\ \. \"\:8080\"/g' /var/www/html/lib/classes/check/environment/publicpaths.php
    fi
}

# Function to upgrade Moodle
upgrade_moodle() {
    echo "Upgrading moodle..."
    php -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --enable
    php -d max_input_vars=10000 /var/www/html/admin/cli/upgrade.php --non-interactive --allow-unstable
    php -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --disable
}

# Check the availability of the primary database
check_db_availability "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$DB_PASS"

# Check the availability of the database replica if specified
if [ -n "$DB_HOST_REPLICA" ]; then
    check_db_availability "$DB_HOST_REPLICA" "${DB_PORT_REPLICA:-$DB_PORT}" "$DB_NAME" "${DB_USER_REPLICA:-$DB_USER}" "${DB_PASS_REPLICA:-$DB_PASS}"
fi

# Execute pre-install commands if the variable is set
if [ -n "$PRE_CONFIGURE_COMMANDS" ]; then
    echo "Executing pre-configure commands..."
    eval "$PRE_CONFIGURE_COMMANDS"
fi

# Add trusted certificates to "ldap-truststore" if specified
if [ "$MY_CERTIFICATES" != 'none' ]; then
    echo "Adding certificates to truststore..."
    echo "$MY_CERTIFICATES" | base64 -d > /etc/openldap/my-certificates/extra.pem
fi

# Generate config.php file if it doesn't exist
if [ ! -f "$config_file" ]; then
    generate_config_file
    set_extra_db_settings
fi

# Detect Moodle >=5.1 (with public/ directory) — do it here, just after config.php exists
if [ -d /var/www/html/public ]; then
    MOODLE_PUBLIC_DIR=true
    export nginx_root_directory="/var/www/html/public"

    sed -i 's|root .*;|root /var/www/html/public;|' /etc/nginx/nginx.conf

    echo "Running composer install for Moodle 5.1+..."
    composer install --no-dev --classmap-authoritative

fi

# Upgrade config.php file
upgrade_config_file

# Check if the database is already installed
if php -d max_input_vars=10000 /var/www/html/admin/cli/isinstalled.php ; then
    install_database
    configure_moodle_settings
    final_configurations
else
    configure_moodle_settings
    echo "Upgrading admin user"
    php -d max_input_vars=10000 /var/www/html/admin/cli/update_admin_user.php --username=$MOODLE_USERNAME --password=$MOODLE_PASSWORD --email=$MOODLE_EMAIL
    if [ -z "$AUTO_UPDATE_MOODLE" ] || [ "$AUTO_UPDATE_MOODLE" = true ]; then

        upgrade_moodle


    else
        echo "Skipped auto update of Moodle"
    fi
fi

# Check if REDIS_HOST is set and not empty
if [ -n "$REDIS_HOST" ]; then
    echo "Configuring redis cache..."
    php -d max_input_vars=10000 /var/www/html/admin/cli/configure_redis.php "${REDIS_HOST}" "${REDIS_PASSWORD}" "${REDIS_USER}"
fi

# Execute post-install commands if the variable is set
if [ -n "$POST_CONFIGURE_COMMANDS" ]; then
    echo "Executing post-configure commands..."
    eval "$POST_CONFIGURE_COMMANDS"
fi