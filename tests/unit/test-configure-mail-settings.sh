#!/usr/bin/env sh
#
# tests/unit/test-configure-mail-settings.sh
#
# Docker-free unit test for configure_moodle_settings() in
# 02-configure-moodle.sh (#194): empty SMTP_* / MOODLE_MAIL_* variables must
# not overwrite the mail settings an admin saved in Moodle's admin pages.
# A fake `php` on PATH records every cfg.php call.
#
# Run from the repository root:
#   ./tests/unit/test-configure-mail-settings.sh
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
for a in "$@"; do
  case "$a" in --name=*) n="${a#--name=}" ;; --set=*) printf '%s=%s\n' "$n" "${a#--set=}" >> "$CFG_LOG" ;; esac
done
PHP
chmod +x "$TMP/bin/php"
sed -n '/^configure_moodle_settings() {/,/^}/p' "$SCRIPT" > "$TMP/fn.sh"

# run_case <name> <env assignments...>: records the cfg.php calls in $TMP/<name>.log
# and the script's stderr in $TMP/<name>.err.
run_case() {
  name="$1"; shift
  : > "$TMP/$name.log"
  env -i PATH="$TMP/bin:/usr/bin:/bin" CFG_LOG="$TMP/$name.log" "$@" \
    sh -c ". '$TMP/fn.sh'; configure_moodle_settings" >/dev/null 2>"$TMP/$name.err"
}

# written <label> <case> <setting> [value]: the setting was written (with exactly
# that value when one is given).
written() {
  if [ $# -eq 4 ]; then grep -qxF "$3=$4" "$TMP/$2.log"; else grep -q "^$3=" "$TMP/$2.log"; fi \
    && echo "  PASS: $1" || { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }
}

not_written() {
  if grep -q "^$3=" "$TMP/$2.log"; then echo "  FAIL: $1"; FAILED=$((FAILED + 1)); else echo "  PASS: $1"; fi
}

MAIL_SETTINGS="smtphosts smtpuser smtppass smtpsecure noreplyaddress emailsubjectprefix"

echo "== empty mail variables leave admin settings alone =="
run_case empty SMTP_HOST= SMTP_PORT= SMTP_USER= SMTP_PASSWORD= SMTP_PROTOCOL= \
  MOODLE_MAIL_NOREPLY_ADDRESS= MOODLE_MAIL_PREFIX=
for s in $MAIL_SETTINGS; do not_written "$s not written" empty "$s"; done
written "unrelated settings still written" empty pathtophp

echo "== empty SMTP_HOST skips the whole SMTP block and warns =="
run_case nohost SMTP_HOST= SMTP_PORT=587 SMTP_USER=u SMTP_PASSWORD=p SMTP_PROTOCOL=tls \
  MOODLE_MAIL_NOREPLY_ADDRESS= MOODLE_MAIL_PREFIX=
for s in smtphosts smtpuser smtppass smtpsecure; do not_written "$s not written" nohost "$s"; done
if grep -q "SMTP_HOST is empty" "$TMP/nohost.err"; then echo "  PASS: warning printed"
else echo "  FAIL: warning printed"; FAILED=$((FAILED + 1)); fi
if [ -s "$TMP/empty.err" ]; then echo "  FAIL: no warning when all empty"; FAILED=$((FAILED + 1))
else echo "  PASS: no warning when all empty"; fi

echo "== set mail variables are applied =="
run_case set SMTP_HOST=mail.example.com SMTP_PORT=25 SMTP_USER= SMTP_PASSWORD= SMTP_PROTOCOL= \
  MOODLE_MAIL_NOREPLY_ADDRESS=noreply@example.com MOODLE_MAIL_PREFIX='[x]'
written "smtphosts" set smtphosts mail.example.com:25
written "smtpuser written empty (no auth)" set smtpuser ""
written "smtppass written empty" set smtppass ""
written "smtpsecure written empty (no TLS)" set smtpsecure ""
written "noreplyaddress" set noreplyaddress noreply@example.com
written "emailsubjectprefix" set emailsubjectprefix "[x]"

echo "== empty SMTP_PORT writes the host alone =="
run_case noport SMTP_HOST=mail.example.com SMTP_PORT=
written "smtphosts without port" noport smtphosts mail.example.com

[ "$FAILED" -eq 0 ] || { echo "$FAILED failure(s)"; exit 1; }
echo "All mail settings tests passed."
