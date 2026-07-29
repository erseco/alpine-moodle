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
#
#   MODE=sync
#     Moodle-context regression test for 010-sync-moodle-code.sh (#103, #161).
#     Must run INSIDE the `app` container. Simulates a stale moodlehtml volume
#     (old stamp + leftover core file + custom plugin + third-party plugin +
#     stale in-tree helper scripts), re-runs the sync script, and asserts
#     config/plugin preservation, core refresh and image-resident helpers.
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

# --------------------------------------------------------------------------
# Moodle-context code-sync regression test (#103)
# --------------------------------------------------------------------------
run_sync_smoke_test() {
  echo "== Moodle code sync smoke test (#103) =="

  html="/var/www/html"
  src="/usr/src/moodle"
  script="/docker-entrypoint-init.d/010-sync-moodle-code.sh"
  stamp="${html}/.alpine-moodle-release"

  src_version_php=""
  if [ -f "${src}/version.php" ]; then
    src_version_php="${src}/version.php"
  elif [ -f "${src}/public/version.php" ]; then
    src_version_php="${src}/public/version.php"
  fi
  if [ -z "$src_version_php" ]; then
    echo "ERROR: immutable Moodle source missing version.php under ${src} (or ${src}/public)"
    exit 1
  fi
  if [ ! -f "$script" ]; then
    echo "ERROR: sync script missing at $script"
    exit 1
  fi
  if [ ! -f "${html}/config.php" ]; then
    echo "ERROR: expected an installed site with config.php at ${html}/config.php"
    exit 1
  fi

  image_ver="$(sed -n 's/^[[:space:]]*\$version[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
    "$src_version_php" | head -n 1)"
  if [ -z "$image_ver" ]; then
    echo "ERROR: could not parse image Moodle \$version from ${src_version_php}"
    exit 1
  fi
  echo "Image Moodle \$version: ${image_ver} (from ${src_version_php})"

  # Layout-aware plugin root: Moodle 5.1+ keeps plugins under public/, and the
  # sync relocates preserved plugins into the image layout, so the fixtures
  # must live where the image expects them.
  plugroot="local"
  if [ -d "${src}/public" ]; then
    plugroot="public/local"
  fi
  cli="/usr/local/lib/alpine-moodle/cli"

  # Snapshot config.php so we can prove it survives the sync.
  config_before="$(cksum < "${html}/config.php")"

  # Simulate a stale volume: old stamp, a leftover core file, a "custom"
  # plugin, an auto-preservable third-party plugin (NOT in
  # EXTRA_PLUGIN_PATHS), and the helper scripts that pre-#161 images shipped
  # inside the tree (the sync must remove them; the image-resident copies at
  # ${cli} are the ones that matter now).
  printf '0.00\n' > "$stamp"
  printf 'stale-core-from-old-image\n' > "${html}/STALE_CORE_FILE_FROM_OLD_IMAGE"
  mkdir -p "${html}/${plugroot}/syncsmoke"
  printf '<?php // custom plugin marker for sync test\n' > "${html}/${plugroot}/syncsmoke/version.php"
  custom_before="$(cksum < "${html}/${plugroot}/syncsmoke/version.php")"
  mkdir -p "${html}/${plugroot}/autosmoke"
  printf '<?php // auto-preserved third-party plugin marker\n' > "${html}/${plugroot}/autosmoke/version.php"
  # Third-party plugins carry their own config.php (every theme does): it must
  # be preserved with the plugin, not used to freeze core config.php files.
  printf '<?php // third-party plugin config\n' > "${html}/${plugroot}/autosmoke/config.php"
  mkdir -p "${html}/admin/cli"
  printf '<?php // stale helper copy from a pre-#161 image\n' > "${html}/admin/cli/update_admin_user.php"

  echo "Re-running sync script with SYNC_MOODLE_CODE=auto and EXTRA_PLUGIN_PATHS=${plugroot}/syncsmoke..."
  SYNC_MOODLE_CODE=auto \
  EXTRA_PLUGIN_PATHS="${plugroot}/syncsmoke" \
  sh "$script"

  stamp_after="$(tr -d '[:space:]' < "$stamp")"
  if [ "$stamp_after" != "$image_ver" ]; then
    echo "ERROR: stamp not updated (got '${stamp_after}', want '${image_ver}')"
    exit 1
  fi
  echo "Stamp updated to ${stamp_after}"

  if [ -e "${html}/STALE_CORE_FILE_FROM_OLD_IMAGE" ]; then
    echo "ERROR: stale core file was not removed by rsync --delete"
    exit 1
  fi
  echo "Stale core file removed."

  config_after="$(cksum < "${html}/config.php")"
  if [ "$config_before" != "$config_after" ]; then
    echo "ERROR: config.php changed during sync (before=${config_before} after=${config_after})"
    exit 1
  fi
  echo "config.php preserved."

  if [ ! -f "${html}/${plugroot}/syncsmoke/version.php" ]; then
    echo "ERROR: EXTRA_PLUGIN_PATHS custom plugin was not restored"
    exit 1
  fi
  custom_after="$(cksum < "${html}/${plugroot}/syncsmoke/version.php")"
  if [ "$custom_before" != "$custom_after" ]; then
    echo "ERROR: custom plugin content changed during sync"
    exit 1
  fi
  echo "Custom plugin ${plugroot}/syncsmoke preserved."

  # Third-party plugin with a version.php must survive WITHOUT being listed in
  # EXTRA_PLUGIN_PATHS — and keep its own config.php (the remui regression:
  # unanchored excludes used to leave a config.php-only skeleton behind).
  if [ ! -f "${html}/${plugroot}/autosmoke/version.php" ] || [ ! -f "${html}/${plugroot}/autosmoke/config.php" ]; then
    echo "ERROR: third-party plugin ${plugroot}/autosmoke was not auto-preserved intact"
    exit 1
  fi
  echo "Third-party plugin ${plugroot}/autosmoke auto-preserved."

  # Helper scripts from pre-#161 images lived inside the tree; the sync must
  # remove the stale copies (the image-resident ones under ${cli} take over).
  if [ -e "${html}/admin/cli/update_admin_user.php" ]; then
    echo "ERROR: stale in-tree helper admin/cli/update_admin_user.php survived the sync"
    exit 1
  fi
  echo "Stale in-tree helper copies removed."

  for helper in isinstalled update_admin_user configure_redis enrol; do
    if [ ! -f "${cli}/${helper}.php" ]; then
      echo "ERROR: image-resident helper ${cli}/${helper}.php is missing"
      exit 1
    fi
  done
  echo "Image-resident helpers present under ${cli}."

  # Second run with matching stamp must be a no-op (leave a local marker alone).
  printf 'local-marker\n' > "${html}/SYNC_NOOP_MARKER"
  SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS="${plugroot}/syncsmoke" sh "$script"
  if [ ! -f "${html}/SYNC_NOOP_MARKER" ]; then
    echo "ERROR: second auto sync with matching versions wiped a local marker (should no-op)"
    exit 1
  fi
  echo "Matching-version auto sync is a no-op."

  # Cleanup test artefacts so they don't pollute the running site.
  rm -f "${html}/SYNC_NOOP_MARKER"
  rm -rf "${html}/${plugroot}/syncsmoke" "${html}/${plugroot}/autosmoke"

  echo "Moodle code sync smoke test passed."
}

if [ "$MODE" = "moosh" ]; then
  run_moosh_smoke_test
  exit 0
fi

if [ "$MODE" = "sync" ]; then
  run_sync_smoke_test
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
