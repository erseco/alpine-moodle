#!/usr/bin/env sh
set -eu

apk --no-cache add curl

# Check that the database is available
echo "Waiting for moodle to be ready"
while ! nc -w 1 app 8080; do
    # Show some progress
    echo -n '.';
    sleep 1;
done
echo "moodle is ready"

# Moodle may still be finishing setup after the TCP port opens.
# Retry an HTTP check, follow redirects, and validate stable Moodle markers.
attempt=1
max_attempts=15
while [ "$attempt" -le "$max_attempts" ]; do
  status="$(curl --silent --show-error --location --output /tmp/moodle.html --write-out '%{http_code}' http://app:8080/ || true)"
  if [ "$status" = "200" ] && grep -Eiq '(Moodle|name="generator" content="Moodle"|/login/index\.php)' /tmp/moodle.html; then
    echo "Moodle HTTP check passed (attempt ${attempt}/${max_attempts})"
    break
  fi

  echo "Waiting for valid Moodle HTTP response (attempt ${attempt}/${max_attempts}, status=${status})"
  attempt=$((attempt + 1))
  sleep 2
done

if [ "$attempt" -gt "$max_attempts" ]; then
  echo "Moodle HTTP check failed after ${max_attempts} attempts"
  echo "Last response headers/body excerpt:"
  head -n 40 /tmp/moodle.html || true
  exit 1
fi

# SQLite-specific verification: check that the database file was created.
if [ "${DB_TYPE:-}" = "sqlite3" ]; then
  echo "Verifying SQLite database file..."
  if [ -f "/var/www/moodledata/sqlite/moodle.sqlite" ]; then
    echo "SQLite database file verified at /var/www/moodledata/sqlite/moodle.sqlite"
    ls -la /var/www/moodledata/sqlite/moodle.sqlite
  else
    echo "ERROR: SQLite database file not found at /var/www/moodledata/sqlite/moodle.sqlite"
    echo "Contents of /var/www/moodledata:"
    ls -laR /var/www/moodledata/ 2>/dev/null || true
    exit 1
  fi
fi

echo "All tests passed."
exit 0
