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

# run_case <name> <env assignments...>: prints the cfg.php calls it made.
run_case() {
  log="$TMP/$1.log"; shift
  : > "$log"
  env -i PATH="$TMP/bin:/usr/bin:/bin" CFG_LOG="$log" "$@" \
    sh -c ". '$TMP/fn.sh'; configure_moodle_settings" >/dev/null
  cat "$log"
}

check() {
  label="$1"; log="$2"; pattern="$3"; want="$4"
  if grep -q "^$pattern" "$log"; then got=present; else got=absent; fi
  if [ "$got" = "$want" ]; then echo "  PASS: $label"
  else echo "  FAIL: $label (expected $want: $pattern)"; FAILED=$((FAILED + 1)); fi
}

echo "== empty mail variables leave admin settings alone =="
run_case empty SMTP_HOST= SMTP_PORT= SMTP_USER= SMTP_PASSWORD= SMTP_PROTOCOL= \
  MOODLE_MAIL_NOREPLY_ADDRESS= MOODLE_MAIL_PREFIX= >/dev/null
for s in smtphosts smtpuser smtppass smtpsecure noreplyaddress emailsubjectprefix; do
  check "$s not written" "$TMP/empty.log" "$s=" absent
done
check "unrelated settings still written" "$TMP/empty.log" "pathtophp=" present

echo "== set mail variables are applied =="
run_case set SMTP_HOST=mail.example.com SMTP_PORT=25 SMTP_USER= SMTP_PASSWORD= SMTP_PROTOCOL= \
  MOODLE_MAIL_NOREPLY_ADDRESS=noreply@example.com MOODLE_MAIL_PREFIX='[x]' >/dev/null
check "smtphosts" "$TMP/set.log" "smtphosts=mail.example.com:25$" present
check "smtpuser written empty (no auth)" "$TMP/set.log" "smtpuser=$" present
check "smtpsecure written empty (no TLS)" "$TMP/set.log" "smtpsecure=$" present
check "noreplyaddress" "$TMP/set.log" "noreplyaddress=noreply@example.com$" present
check "emailsubjectprefix" "$TMP/set.log" "emailsubjectprefix=\[x\]$" present

[ "$FAILED" -eq 0 ] || { echo "$FAILED failure(s)"; exit 1; }
echo "All mail settings tests passed."
