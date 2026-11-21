#!/usr/bin/env bash
# MOODLE_VERSION=v5.3.0 tests/database-tls-test.sh mariadb|mysqli|pgsql
set -euo pipefail
cd "$(dirname "$0")/.."

backend=${1:?usage: tests/database-tls-test.sh mariadb|mysqli|pgsql}
case "$backend" in
    mariadb) database=mariadb:11.4; port=3306 ;;
    mysqli) database=mysql:8.4; port=3306 ;;
    pgsql) database=postgres:17-alpine; port=5432 ;;
    *) echo "Unknown backend: $backend" >&2; exit 1 ;;
esac

tls=$(mktemp -d)
# Docker Desktop shares /tmp as /private/tmp.
tls=$(cd "$tls" && pwd -P)
project=moodle-tls-$(printf '%s' "${tls##*.}" | LC_ALL=C tr '[:upper:]' '[:lower:]')
app=$project-app
db=$project-db
cleanup() {
    if [ "$1" != 0 ]; then
        docker logs "$app" || true
        docker logs "$db" || true
    fi
    docker rm -fv "$app" "$db" >/dev/null 2>&1 || true
    docker volume rm "$project-html" "$project-data" >/dev/null 2>&1 || true
    docker network rm "$project" >/dev/null 2>&1 || true
    if [ -z "${MOODLE_TEST_IMAGE:-}" ]; then
        docker image rm "$project" >/dev/null 2>&1 || true
    fi
    rm -rf "$tls"
}
trap 'cleanup $?' EXIT

image=${MOODLE_TEST_IMAGE:-$project}
if [ -z "${MOODLE_TEST_IMAGE:-}" ]; then
    version=${MOODLE_VERSION:-v5.3.0}
    runtime=$(bash scripts/image-runtime.sh "$version")
    docker build -t "$image" --build-arg MOODLE_VERSION="$version" \
        --build-arg PHP_VERSION="$(sed -n 's/^php=//p' <<< "$runtime")" \
        --build-arg PHP_WEBSERVER_VERSION="$(sed -n 's/^base=//p' <<< "$runtime")" .
fi

# Run the config regressions with the image's actual BusyBox shell and sed.
docker run --rm --entrypoint /bin/sh -v "$PWD:/repo:ro" "$image" /repo/tests/unit/test-configure-db-tls.sh

openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=Moodle-test-CA \
    -keyout "$tls/ca.key" -out "$tls/ca.crt" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj /CN=db \
    -keyout "$tls/server.key" -out "$tls/server.csr" 2>/dev/null
printf 'subjectAltName=DNS:db\nextendedKeyUsage=serverAuth\n' > "$tls/extensions"
openssl x509 -req -in "$tls/server.csr" -CA "$tls/ca.crt" -CAkey "$tls/ca.key" \
    -CAcreateserial -days 2 -extfile "$tls/extensions" -out "$tls/server.crt" 2>/dev/null
rm "$tls/ca.key" "$tls/server.csr"
chmod 755 "$tls"
chmod 644 "$tls/server.key"
# Keep the normal trust roots for Moodle's Composer bootstrap.
docker run --rm --entrypoint cat "$image" /etc/ssl/certs/ca-certificates.crt > "$tls/client-ca.crt"
cat "$tls/ca.crt" >> "$tls/client-ca.crt"

docker network create "$project" >/dev/null
database_args=(--name "$db" --network "$project" --network-alias db -v "$tls:/tls:ro")
if [ "$backend" = pgsql ]; then
    printf 'local all all trust\nhostssl all all all scram-sha-256\n' > "$tls/pg_hba.conf"
    docker run -d "${database_args[@]}" -e POSTGRES_USER=moodle -e POSTGRES_PASSWORD=moodle \
        "$database" sh -ec '
            cp /tls/server.key /tmp/server.key
            chown postgres /tmp/server.key
            chmod 600 /tmp/server.key
            exec docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file=/tls/server.crt \
                -c ssl_key_file=/tmp/server.key -c hba_file=/tls/pg_hba.conf
        ' >/dev/null
else
    docker run -d "${database_args[@]}" -e MYSQL_ROOT_PASSWORD=test-root -e MYSQL_DATABASE=moodle \
        -e MYSQL_USER=moodle -e MYSQL_PASSWORD=moodle "$database" --require-secure-transport=ON \
        --ssl-ca=/tls/ca.crt --ssl-cert=/tls/server.crt --ssl-key=/tls/server.key \
        --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci >/dev/null
fi

app_args=(--network "$project" -v "$project-html:/var/www/html" -v "$project-data:/var/www/moodledata"
    -v "$tls/client-ca.crt:/tls/client-ca.crt:ro" -e SSL_CERT_FILE=/tls/client-ca.crt -e PGSSLROOTCERT=/tls/client-ca.crt
    -e DB_TYPE="$backend" -e DB_HOST=db -e DB_PORT="$port" -e SITE_URL=http://app:8080
    -e AUTO_UPDATE_MOODLE=false -e SMTP_HOST=)

assert_boot() {
    local expected=$1
    local attempt
    for ((attempt = 0; attempt < 120; attempt++)); do
        if docker exec "$app" nc -w 1 127.0.0.1 8080 </dev/null >/dev/null 2>&1; then
            # shellcheck disable=SC2016
            docker exec "$app" php -r '
                define("CLI_SCRIPT", true);
                require "/var/www/html/config.php";
                exit($CFG->dboptions["ssl"] !== $argv[1] || !$DB->get_tables());
            ' "$expected"
            return
        fi
        if [ "$(docker inspect -f '{{.State.Running}}' "$app")" = false ]; then
            break
        fi
        sleep 2
    done
    echo "Moodle failed to start with expected DB_SSL=$expected" >&2
    return 1
}

start() {
    docker run -d --name "$app" "${app_args[@]}" -e DB_SSL="$1" "$image" >/dev/null
    assert_boot "$2"
}

start require require
# Simulate a persisted config that predates the environment-managed setting.
docker exec "$app" sed -i '/^\$CFG->dboptions = .*); require_once/s/^.*); require_once/require_once/' /var/www/html/config.php
docker restart "$app" >/dev/null
assert_boot require
docker rm -fv "$app" >/dev/null
start verify-full verify-full
before=$(docker exec "$app" cksum /var/www/html/config.php)
docker restart "$app" >/dev/null
assert_boot verify-full
test "$(docker exec "$app" cksum /var/www/html/config.php)" = "$before"
docker rm -fv "$app" >/dev/null
start '' verify-full
test "$(docker exec "$app" cksum /var/www/html/config.php)" = "$before"

echo "Database TLS integration passed for $backend."
