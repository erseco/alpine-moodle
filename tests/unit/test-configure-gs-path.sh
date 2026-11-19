#!/usr/bin/env sh
#
# tests/unit/test-configure-gs-path.sh
#
# Docker-free unit test for configure_moodle_settings() in
# 02-configure-moodle.sh: the image ships Ghostscript for the Annotate PDF
# feedback plugin, so an unset or empty pathtogs is pointed at /usr/bin/gs,
# while a value already saved in Moodle is kept. A fake `php` on PATH stands in
# for cfg.php: reads print $STORED_PATHTOGS (exit 3 when unset, like cfg.php)
# and every write is recorded.
#
# Run from the repository root:
#   ./tests/unit/test-configure-gs-path.sh
#
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
SCRIPT="${ROOT}/rootfs/docker-entrypoint-init.d/02-configure-moodle.sh"
FAILED=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/bin/php" <<'PHP'
#!/bin/sh
n=; write=
for a in "$@"; do
  case "$a" in --name=*) n="${a#--name=}" ;; --set=*) write=1; printf '%s=%s\n' "$n" "${a#--set=}" >> "$CFG_LOG" ;; esac
done
if [ -z "$write" ] && [ "$n" = pathtogs ]; then
  [ -n "${STORED_PATHTOGS+set}" ] || exit 3
  printf '%s\n' "$STORED_PATHTOGS"
fi
PHP
chmod +x "$TMP/bin/php"
sed -n '/^configure_moodle_settings() {/,/^}/p' "$SCRIPT" > "$TMP/fn.sh"

# run_case <name> <env assignments...>: records the cfg.php writes in $TMP/<name>.log.
run_case() {
  name="$1"; shift
  : > "$TMP/$name.log"
  env -i PATH="$TMP/bin:/usr/bin:/bin" CFG_LOG="$TMP/$name.log" "$@" \
    sh -c ". '$TMP/fn.sh'; configure_moodle_settings" >/dev/null 2>&1
}

check() {
  if [ "$2" = "written" ]; then grep -qxF "pathtogs=/usr/bin/gs" "$TMP/$3.log"; else ! grep -q "^pathtogs=" "$TMP/$3.log"; fi \
    && echo "  PASS: $1" || { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }
}

echo "== pathtogs is filled in only when it is unset or empty =="
run_case unset
check "unset pathtogs set to /usr/bin/gs" written unset
run_case empty STORED_PATHTOGS=
check "empty pathtogs set to /usr/bin/gs" written empty
run_case default STORED_PATHTOGS=/usr/bin/gs
check "default pathtogs not rewritten" not_written default
run_case custom STORED_PATHTOGS=/opt/ghostscript/bin/gs
check "custom pathtogs kept" not_written custom

[ "$FAILED" -eq 0 ] || { echo "$FAILED failure(s)"; exit 1; }
echo "All pathtogs tests passed."
