#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
tags='4.3.1
v4.4.12
v4.5.0-1
v4.5.9
v4.5.14
v4.5.15
v5.2
v5.2.3
v5.2.4
v5.2.3-php84
v5.2.4-php84
v5.3.0-beta
v5.3.0-rc2
v5.3.0
v5.3.0;id'
plan=$(bash scripts/image-aliases.sh plan <<< "$tags")
expected='v4.5.9 4.5.9
v4.5.14 4.5.14
v4.5.15 4.5.15
v4.5.15 4.5
v4.5.15 4
v5.2.3 5.2.3
v5.2.3-php84 5.2.3-php84
v5.2.4 5.2.4
v5.2.4 5.2
v5.2.4-php84 5.2.4-php84
v5.2.4-php84 5.2-php84
v5.3.0 5.3.0
v5.3.0 5.3
v5.3.0 5
v5.3.0-beta 5.3.0-beta
v5.3.0-rc2 5.3.0-rc2'
# Compare as sets: sort -V orders prerelease suffixes differently across platforms.
[[ $(sort <<< "$plan") == $(sort <<< "$expected") ]] || {
  diff <(sort <<< "$expected") <(sort <<< "$plan") >&2; exit 1;
}
# `! cmd` never trips errexit, so negative checks go through a function.
absent() { ! grep -q "$1" <<< "$2"; }
# A newer patch moves the series aliases, never the exact ones.
plan=$(bash scripts/image-aliases.sh plan <<< "$tags"$'\nv5.2.10\nv5.10.0')
grep -qx 'v5.2.10 5.2' <<< "$plan"
grep -qx 'v5.2.4 5.2.4' <<< "$plan"
absent '^v5.2.4 5.2$' "$plan"
grep -qx 'v5.10.0 5' <<< "$plan"
absent '^v5.3.0 5$' "$plan"
# -php84 only gets minor series aliases: 5 is already PHP 8.4 since 5.3.
absent ' 5-php84$' "$plan"

readme=$(bash scripts/image-aliases.sh readme v5.3.0 <<< "$tags")
expected='- `v5.3.0`, `5.3.0`, `5.3`, `5`, `latest` (PHP 8.4)
- `v5.2.4`, `5.2.4`, `5.2` (PHP 8.3) · `v5.2.4-php84`, `5.2.4-php84`, `5.2-php84` (PHP 8.4)
- `v4.5.15`, `4.5.15`, `4.5`, `4` (PHP 8.3)'
[[ "$readme" == "$expected" ]] || { diff <(echo "$expected") <(echo "$readme") >&2; exit 1; }
# Without a current stable release no entry claims latest.
absent latest "$(bash scripts/image-aliases.sh readme <<< "$tags")"
if bash scripts/image-aliases.sh bogus < /dev/null >/dev/null 2>&1; then
  echo 'Accepted unknown command' >&2; exit 1
fi
echo 'Image aliases: all cases passed.'
