#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
script="$root/rootfs/docker-entrypoint-init.d/02-configure-moodle.sh"
export DB_TYPE
export alpine_moodle_cli
alpine_moodle_cli="$root/rootfs/usr/local/lib/alpine-moodle/cli"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
config_file="$tmp/config.php"

# Load the actual startup steps without touching container paths.
# shellcheck disable=SC2016
sed -n '/^case "\${DB_SSL:-}" in/,/^esac/p' "$script" > "$tmp/validate.sh"
sed -n '/^generate_config_file() {/,/^}/p; /^set_tls_settings() {/,/^}/p' "$script" > "$tmp/functions.sh"
# shellcheck disable=SC1091
. "$tmp/functions.sh"

for DB_TYPE in mariadb mysqli pgsql sqlite3; do
    for DB_SSL in prefer disable garbage; do
        # shellcheck disable=SC1091
        if ( . "$tmp/validate.sh" ) 2>"$tmp/error"; then
            echo "Accepted unsupported DB_SSL=$DB_SSL" >&2
            exit 1
        fi
        grep -q 'DB_SSL must be require, verify-full, or empty' "$tmp/error"
    done
done
test ! -e "$config_file"

# Test the generated root config with Moodle's legacy and public/ bootstraps.
for layout in legacy public; do
    rm -f "$config_file"
    mkdir -p "$tmp/lib" "$tmp/public/lib"
    printf '%s\n' '<?php return;' > "$tmp/public/lib/setup.php"
    if [ "$layout" = public ]; then
        printf '%s\n' '<?php require __DIR__ . "/../public/lib/setup.php";' > "$tmp/lib/setup.php"
    else
        printf '%s\n' '<?php return;' > "$tmp/lib/setup.php"
    fi

    DB_SSL=require DB_TYPE=mariadb DB_HOST=db DB_NAME=moodle DB_USER=moodle DB_PASS="a&b'c" DB_PORT=3306 \
        DB_PREFIX=mdl_ SITE_URL=http://app:8080 generate_config_file
    DB_TYPE=mariadb DB_SSL=require set_tls_settings
    php -l "$config_file" >/dev/null
    # shellcheck disable=SC2016
    php -r 'require $argv[1]; exit($CFG->dbpass !== $argv[2] || $CFG->dboptions["ssl"] !== "require");' \
        "$config_file" "a&b'c"
done

# Existing options can be inline, standalone or computed PHP.
cat > "$config_file" <<'PHP'
<?php
$CFG = new stdClass();
$CFG->dboptions = ['ssl' => 'prefer', 'fetchbuffersize' => 0];
$CFG->dboptions['readonly'] = ['instance' => ['dbpass' => "a&b|c'\\d"]];
$CFG->dboptions['ssl'] = 'require';
$CFG->test = <<<'EXAMPLE'
require_once(__DIR__ . '/lib/setup.php');
EXAMPLE;
require_once(__DIR__ . '/lib/setup.php'); // Moodle bootstrap.
PHP
cp "$config_file" "$tmp/original"
unset DB_SSL
DB_TYPE=pgsql set_tls_settings
DB_TYPE=pgsql DB_SSL='' set_tls_settings
DB_TYPE=sqlite3 DB_SSL=require set_tls_settings
cmp "$tmp/original" "$config_file"

for DB_TYPE in mariadb mysqli pgsql; do
    for DB_SSL in require verify-full; do
        set_tls_settings
        php -l "$config_file" >/dev/null
        # shellcheck disable=SC2016
        php -r '
            require $argv[1];
            exit($CFG->dboptions["ssl"] !== $argv[2]
                || $CFG->dboptions["fetchbuffersize"] !== 0
                || $CFG->dboptions["readonly"]["instance"]["dbpass"] !== $argv[3]);
        ' "$config_file" "$DB_SSL" "a&b|c'\\d"
        cp "$config_file" "$tmp/applied"
        set_tls_settings
        DB_SSL='' set_tls_settings
        cmp "$tmp/applied" "$config_file"
        # shellcheck disable=SC2016
        test "$(grep -Fc '+ ($CFG->dboptions ?? [])' "$config_file")" = 1
    done
done

printf '%s\n' '<?php return require_once(__DIR__ . "/lib/setup.php");' > "$config_file"
cp "$config_file" "$tmp/unsupported"
if DB_TYPE=pgsql DB_SSL=require set_tls_settings 2>"$tmp/error"; then
    echo "Changed a config without a standalone Moodle bootstrap" >&2
    exit 1
fi
grep -q 'could not locate' "$tmp/error"
cmp "$tmp/unsupported" "$config_file"

echo "Database TLS configuration tests passed."
