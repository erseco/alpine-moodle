#!/usr/bin/env bash
# Disposable real database + code/data volumes; never uses deployment volumes.
set -euo pipefail
cd "$(dirname "$0")/.."
export COMPOSE_PROJECT_NAME="moodle53upgrade${RANDOM}"
export UPGRADE_IMAGE="alpine-moodle-upgrade:45"
dc() { docker compose -f tests/upgrade.compose.yml "$@"; }
cleanup() {
  local rc=$?
  if (( rc != 0 )); then dc logs --no-color; fi
  dc down --volumes --remove-orphans
}
trap cleanup EXIT
docker build --build-arg MOODLE_VERSION=v4.5.14 --build-arg PHP_VERSION=83 --build-arg PHP_WEBSERVER_VERSION=3.20 -t "$UPGRADE_IMAGE" .
docker build --build-arg MOODLE_VERSION=v5.3.0-beta --build-arg PHP_VERSION=84 --build-arg PHP_WEBSERVER_VERSION=3.23 -t alpine-moodle-upgrade:53 .
dc up -d app
dc run --rm sut
dc exec -T app php /tmp/upgrade-fixture.php seed
# Install the fixture plugin while still on 4.5 before testing its migration.
dc exec -T app php /var/www/html/admin/cli/upgrade.php --non-interactive
dc stop app
export UPGRADE_IMAGE=alpine-moodle-upgrade:53
dc up -d app
dc run --rm sut
dc exec -T app php /tmp/upgrade-fixture.php verify
dc exec -T app sh /tmp/run_tests.sh moosh
dc exec -T app sh /tmp/run_tests.sh checks
dc exec -T app php /var/www/html/public/admin/cli/cron.php
dc restart app
dc run --rm sut
dc exec -T app php /tmp/upgrade-fixture.php verify
echo 'PASS: real Moodle 4.5/PHP 8.3 -> 5.3 beta/PHP 8.4 upgrade and restart'
