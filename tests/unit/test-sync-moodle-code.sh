#!/usr/bin/env sh
#
# tests/unit/test-sync-moodle-code.sh
#
# Fast, docker-free unit tests for 010-sync-moodle-code.sh.
# Builds a miniature "image" tree and a "volume" tree, exercises auto/always/never
# and EXTRA_PLUGIN_PATHS preservation.
#
# Run from the repository root:
#   ./tests/unit/test-sync-moodle-code.sh
#
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
SCRIPT="${ROOT}/rootfs/docker-entrypoint-init.d/010-sync-moodle-code.sh"
FAILED=0

if [ ! -x "$SCRIPT" ] && [ -f "$SCRIPT" ]; then
  chmod +x "$SCRIPT"
fi
if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: sync script not found at $SCRIPT"
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync is required for these tests"
  exit 1
fi

assert_eq() {
  label="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
  else
    echo "  FAIL: $label (expected='$expected' actual='$actual')"
    FAILED=$((FAILED + 1))
  fi
}

assert_file() {
  label="$1"
  path="$2"
  if [ -e "$path" ]; then
    echo "  PASS: $label"
  else
    echo "  FAIL: $label (missing $path)"
    FAILED=$((FAILED + 1))
  fi
}

assert_no_file() {
  label="$1"
  path="$2"
  if [ ! -e "$path" ]; then
    echo "  PASS: $label"
  else
    echo "  FAIL: $label (still exists: $path)"
    FAILED=$((FAILED + 1))
  fi
}

# Tiny Moodle-like tree: only version.php + a couple of markers.
seed_tree() {
  dest="$1"
  ver="$2"
  marker_content="$3"
  rm -rf "$dest"
  mkdir -p "$dest/lib" "$dest/mod/forum"
  printf '%s\n' "<?php" "\$version  = ${ver};" "\$release  = 'test';" "\$branch   = '000';" \
    > "$dest/version.php"
  printf '%s\n' "$marker_content" > "$dest/lib/moodlelib.php"
  printf 'core-forum\n' > "$dest/mod/forum/version.php"
}

run_sync() {
  # shellcheck disable=SC2030,SC2031
  SYNC_MOODLE_CODE="${SYNC_MOODLE_CODE:-auto}" \
  EXTRA_PLUGIN_PATHS="${EXTRA_PLUGIN_PATHS:-}" \
  SYNC_PRESERVE_PLUGINS="${SYNC_PRESERVE_PLUGINS:-true}" \
  MOODLE_SRC_DIR="$SRC" \
  MOODLE_HTML_DIR="$HTML" \
  sh "$SCRIPT"
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
SRC="${WORKDIR}/src"
HTML="${WORKDIR}/html"

echo "== test 1: auto seeds empty volume =="
seed_tree "$SRC" "2025041402.00" "image-core-v2"
rm -rf "$HTML"
mkdir -p "$HTML"
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS= run_sync
assert_file "version.php copied" "${HTML}/version.php"
assert_eq "stamp written" "2025041402.00" "$(tr -d '[:space:]' < "${HTML}/.alpine-moodle-release")"
assert_eq "core content from image" "image-core-v2" "$(cat "${HTML}/lib/moodlelib.php")"

echo "== test 2: auto is a no-op when versions match =="
# Drop a local marker; sync must NOT wipe it if versions already match.
printf 'local-only\n' > "${HTML}/local-only.txt"
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS= run_sync
assert_file "local file kept when in sync" "${HTML}/local-only.txt"

echo "== test 3: auto upgrades and deletes leftover core files =="
seed_tree "$SRC" "2025041402.00" "image-core-v2"
seed_tree "$HTML" "2025041401.00" "old-core-v1"
printf 'stale-core-file\n' > "${HTML}/STALE_CORE_FILE"
printf '<?php // site config\n' > "${HTML}/config.php"
mkdir -p "${HTML}/mod/attendance"
printf 'custom-plugin\n' > "${HTML}/mod/attendance/version.php"
# Also drop a local-only file that is NOT in EXTRA_PLUGIN_PATHS → should be deleted by --delete
printf 'junk\n' > "${HTML}/will-be-deleted.txt"

SYNC_MOODLE_CODE=auto \
EXTRA_PLUGIN_PATHS="mod/attendance" \
run_sync

assert_eq "stamp upgraded" "2025041402.00" "$(tr -d '[:space:]' < "${HTML}/.alpine-moodle-release")"
assert_eq "core replaced" "image-core-v2" "$(cat "${HTML}/lib/moodlelib.php")"
assert_eq "config.php preserved" "<?php // site config" "$(cat "${HTML}/config.php")"
assert_eq "custom plugin preserved" "custom-plugin" "$(cat "${HTML}/mod/attendance/version.php")"
assert_file "core mod/forum from image" "${HTML}/mod/forum/version.php"
assert_no_file "stale core file removed" "${HTML}/STALE_CORE_FILE"
assert_no_file "non-extra local file removed" "${HTML}/will-be-deleted.txt"

echo "== test 4: never never syncs =="
seed_tree "$SRC" "2025041402.00" "image-core-v2"
seed_tree "$HTML" "2025041401.00" "old-core-v1"
printf 'stale\n' > "${HTML}/STALE_CORE_FILE"
SYNC_MOODLE_CODE=never EXTRA_PLUGIN_PATHS= run_sync
assert_eq "core unchanged under never" "old-core-v1" "$(cat "${HTML}/lib/moodlelib.php")"
assert_file "stale kept under never" "${HTML}/STALE_CORE_FILE"

echo "== test 5: always syncs even when versions match =="
seed_tree "$SRC" "2025041402.00" "image-core-v2"
seed_tree "$HTML" "2025041402.00" "tampered-core"
printf '2025041402.00\n' > "${HTML}/.alpine-moodle-release"
printf 'local-only\n' > "${HTML}/local-only.txt"
SYNC_MOODLE_CODE=always EXTRA_PLUGIN_PATHS= run_sync
assert_eq "always re-applies image core" "image-core-v2" "$(cat "${HTML}/lib/moodlelib.php")"
assert_no_file "always deletes local-only files" "${HTML}/local-only.txt"

echo "== test 6: rejects unsafe EXTRA_PLUGIN_PATHS =="
seed_tree "$SRC" "2025041402.00" "image-core-v2"
seed_tree "$HTML" "2025041401.00" "old-core-v1"
set +e
out="$(
  SYNC_MOODLE_CODE=auto \
  EXTRA_PLUGIN_PATHS="../etc/passwd" \
  MOODLE_SRC_DIR="$SRC" \
  MOODLE_HTML_DIR="$HTML" \
  sh "$SCRIPT" 2>&1
)"
rc=$?
set -e
if [ "$rc" -ne 0 ] && echo "$out" | grep -qi 'invalid EXTRA_PLUGIN_PATHS'; then
  echo "  PASS: unsafe path rejected"
else
  echo "  FAIL: unsafe path was not rejected (rc=$rc)"
  echo "$out"
  FAILED=$((FAILED + 1))
fi

echo "== test 7: Moodle 5.1+ public/ version.php layout =="
# Image tree only has public/version.php (no root version.php).
rm -rf "$SRC" "$HTML"
mkdir -p "$SRC/public/lib" "$HTML/public/lib"
printf '%s\n' "<?php" "\$version  = 2026071400.00;" > "$SRC/public/version.php"
printf 'image-public-core\n' > "$SRC/public/lib/moodlelib.php"
printf '%s\n' "<?php" "\$version  = 2025041401.00;" > "$HTML/public/version.php"
printf 'old-public-core\n' > "$HTML/public/lib/moodlelib.php"
printf '<?php // cfg\n' > "$HTML/config.php"
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS= run_sync
assert_eq "public layout stamp" "2026071400.00" "$(tr -d '[:space:]' < "${HTML}/.alpine-moodle-release")"
assert_eq "public layout core replaced" "image-public-core" "$(cat "${HTML}/public/lib/moodlelib.php")"
assert_file "config.php still present" "${HTML}/config.php"

echo "== test 8: nested config.php files are synced (only the root one is preserved) =="
# Regression for #161 follow-up: the rsync excludes were unanchored, so ANY file
# named config.php (every Moodle theme has one) was frozen at the old version.
seed_tree "$SRC" "2025041402.00" "image-core-v2"
mkdir -p "$SRC/theme/boost"
printf 'image-theme-cfg\n' > "$SRC/theme/boost/config.php"
seed_tree "$HTML" "2025041401.00" "old-core-v1"
mkdir -p "$HTML/theme/boost"
printf 'old-theme-cfg\n' > "$HTML/theme/boost/config.php"
printf '<?php // site config\n' > "$HTML/config.php"
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS= run_sync
assert_eq "nested theme config.php updated from image" "image-theme-cfg" "$(cat "${HTML}/theme/boost/config.php")"
assert_eq "root config.php preserved" "<?php // site config" "$(cat "${HTML}/config.php")"

echo "== test 9: seeding an empty volume copies nested config.php files =="
seed_tree "$SRC" "2025041402.00" "image-core-v2"
mkdir -p "$SRC/theme/boost"
printf 'image-theme-cfg\n' > "$SRC/theme/boost/config.php"
rm -rf "$HTML"
mkdir -p "$HTML"
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS= run_sync
assert_file "nested theme config.php seeded" "${HTML}/theme/boost/config.php"

echo "== test 10: third-party plugins (with version.php) are auto-preserved =="
seed_tree "$SRC" "2025041402.00" "image-core-v2"
seed_tree "$HTML" "2025041401.00" "old-core-v1"
printf '<?php // site config\n' > "$HTML/config.php"
mkdir -p "$HTML/mod/thirdparty" "$HTML/vendor/somepkg"
printf 'thirdparty-plugin\n' > "$HTML/mod/thirdparty/version.php"
printf 'thirdparty-lib\n' > "$HTML/mod/thirdparty/lib.php"
# vendor/ must never be treated as a plugin, even if a package ships version.php
printf 'composer-pkg\n' > "$HTML/vendor/somepkg/version.php"
printf 'junk\n' > "$HTML/junk.txt"
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS= SYNC_PRESERVE_PLUGINS=true run_sync
assert_eq "third-party plugin auto-preserved" "thirdparty-plugin" "$(cat "${HTML}/mod/thirdparty/version.php" 2>/dev/null || true)"
assert_file "third-party plugin content intact" "${HTML}/mod/thirdparty/lib.php"
assert_no_file "vendor/ not auto-preserved" "${HTML}/vendor/somepkg"
assert_no_file "junk file removed" "${HTML}/junk.txt"

echo "== test 11: SYNC_PRESERVE_PLUGINS=false deletes third-party plugins entirely =="
# Regression for the half-deleted theme (remui): the unanchored config.php
# exclude used to protect <plugin>/config.php, leaving a broken skeleton.
seed_tree "$SRC" "2025041402.00" "image-core-v2"
seed_tree "$HTML" "2025041401.00" "old-core-v1"
printf '<?php // site config\n' > "$HTML/config.php"
mkdir -p "$HTML/theme/fancy"
printf 'fancy-version\n' > "$HTML/theme/fancy/version.php"
printf 'fancy-theme-cfg\n' > "$HTML/theme/fancy/config.php"
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS= SYNC_PRESERVE_PLUGINS=false run_sync
assert_no_file "third-party theme fully removed (no config.php skeleton)" "${HTML}/theme/fancy"

echo "== test 12: auto-preserved plugins are relocated into public/ on 5.1+ upgrades =="
# Old pre-5.1 volume (plugins at the root) upgraded to a public/-layout image:
# preserved plugins must land under public/ or Moodle will never see them.
rm -rf "$SRC" "$HTML"
mkdir -p "$SRC/public/lib" "$SRC/public/mod/forum"
printf '%s\n' "<?php" "\$version  = 2026071400.00;" > "$SRC/public/version.php"
printf 'image-public-core\n' > "$SRC/public/lib/moodlelib.php"
printf 'core-forum\n' > "$SRC/public/mod/forum/version.php"
seed_tree "$HTML" "2025041401.00" "old-core-v1"
printf '<?php // site config\n' > "$HTML/config.php"
mkdir -p "$HTML/mod/attendance"
printf 'attendance-plugin\n' > "$HTML/mod/attendance/version.php"
# NOTE: assignments before a *function* call persist in POSIX sh, so always
# pass SYNC_PRESERVE_PLUGINS explicitly after test 11 set it to false.
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS= SYNC_PRESERVE_PLUGINS=true run_sync
assert_eq "plugin relocated under public/" "attendance-plugin" "$(cat "${HTML}/public/mod/attendance/version.php" 2>/dev/null || true)"
assert_no_file "plugin not left at the pre-5.1 path" "${HTML}/mod/attendance"

echo "== test 13: EXTRA_PLUGIN_PATHS entries are relocated into public/ too =="
rm -rf "$SRC" "$HTML"
mkdir -p "$SRC/public/lib"
printf '%s\n' "<?php" "\$version  = 2026071400.00;" > "$SRC/public/version.php"
printf 'image-public-core\n' > "$SRC/public/lib/moodlelib.php"
seed_tree "$HTML" "2025041401.00" "old-core-v1"
printf '<?php // site config\n' > "$HTML/config.php"
mkdir -p "$HTML/local/custom"
printf 'custom-no-versionphp\n' > "$HTML/local/custom/lib.php"
SYNC_MOODLE_CODE=auto EXTRA_PLUGIN_PATHS="local/custom" run_sync
assert_eq "EXTRA path relocated under public/" "custom-no-versionphp" "$(cat "${HTML}/public/local/custom/lib.php" 2>/dev/null || true)"
assert_no_file "EXTRA path not left at the pre-5.1 location" "${HTML}/local/custom"

echo
if [ "$FAILED" -eq 0 ]; then
  echo "All unit tests passed."
  exit 0
fi
echo "FAILED: ${FAILED} assertion(s)."
exit 1
