#!/usr/bin/env sh
set -eu

# run_tests.sh [MODE]
#
#   MODE=all (default)
#     Black-box readiness + HTTP web check. Runs from the `sut` container against
#     the `app` service: waits for the port, then asserts an HTTP 200 homepage
#     carrying stable Moodle markers. Also verifies the SQLite DB file when
#     DB_TYPE=sqlite3.
#
#   MODE=moosh
#     Moodle-context `moosh` smoke test. Must run INSIDE the `app` container,
#     because moosh needs the Moodle codebase and DB access, which only exist
#     there. Fails if moosh cannot bootstrap Moodle (the PR #149 regression on
#     the 5.1+ public/ layout).
MODE="${1:-all}"

# --------------------------------------------------------------------------
# Moodle-context moosh smoke test
# --------------------------------------------------------------------------
run_moosh_smoke_test() {
  echo "== Moodle-context moosh smoke test =="

  # Diagnostics: report the detected code root and the build version so a failure
  # immediately shows which layout / version was under test.
  if [ -f /var/www/html/public/version.php ]; then
    echo "Layout: Moodle 5.1+ public/ (code root: /var/www/html/public)"
  else
    echo "Layout: legacy pre-5.1 (code root: /var/www/html)"
  fi
  echo "MOODLE_VERSION (build arg): ${MOODLE_VERSION:-<unset>}"

  if ! command -v moosh >/dev/null 2>&1; then
    echo "ERROR: moosh not found in PATH; this mode must run inside the app container."
    exit 1
  fi

  # role-list requires a bootstrapped Moodle + DB. If moosh cannot detect the
  # Moodle install it prints only its global commands ("No command provided,
  # possible commands in current context: ..."), which is exactly the PR #149
  # regression on the 5.1+ public/ layout. role-list is read-only, deterministic
  # and works across Moodle 4.5 -> main.
  echo "Running: moosh role-list"
  set +e
  moosh_output="$(moosh role-list 2>&1)"
  moosh_rc=$?
  set -e

  echo "----- moosh role-list output (rc=${moosh_rc}) -----"
  echo "$moosh_output"
  echo "---------------------------------------------------"

  if [ "$moosh_rc" -ne 0 ]; then
    echo "ERROR: 'moosh role-list' exited with code ${moosh_rc}."
    exit 1
  fi

  if echo "$moosh_output" | grep -qiE 'No command provided|possible commands in current context'; then
    echo "ERROR: moosh returned its global/no-bootstrap command list; Moodle context did not load."
    echo "This is the PR #149 regression (moosh pointed at the wrong code root)."
    exit 1
  fi

  # A bootstrapped site always exposes the standard archetype roles. Their
  # shortnames are not localised, so this is stable across versions/languages.
  if ! echo "$moosh_output" | grep -qiE '(manager|editingteacher|student|guest)'; then
    echo "ERROR: moosh role-list did not list the standard Moodle roles; unexpected output."
    exit 1
  fi

  echo "moosh Moodle-context smoke test passed."
}

if [ "$MODE" = "moosh" ]; then
  run_moosh_smoke_test
  exit 0
fi

# --------------------------------------------------------------------------
# Default: black-box readiness + HTTP web check
# --------------------------------------------------------------------------
apk --no-cache add curl

# Wait for the app port to open, bounded by a deadline so a build that never
# starts (crash-loop / broken layout) fails cleanly instead of hanging forever.
echo "Waiting for moodle to be ready"
deadline=$(( $(date +%s) + 600 ))   # up to 10 minutes for first-boot install
while ! nc -w 1 app 8080; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "ERROR: app:8080 did not open within 10 minutes; Moodle failed to start."
        exit 1
    fi
    # Show some progress
    printf '.';
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
    # Break to continue with DB-specific checks below.
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
