#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check() {
  local output
  output=$(bash scripts/release-policy.sh "$1" "$2")
  [[ "$output" == "version=$1"$'\n'"latest=$3" ]]
}
check v5.2.3 v5.2.3 false
check v5.2.2 v5.2.3 false
check v4.5.14 v5.2.3 false
check v5.3.0-beta v5.2.3 false
check v5.3.0-rc1 v5.2.3 false
check v5.3.0 v5.3.0 true
check v5.3.0 v5.3.1 false
check main v5.2.3 false
for invalid in v5.2.3-php84 'v5.2.3;id' 'refs/heads/main'; do
  if bash scripts/release-policy.sh "$invalid" >/dev/null 2>&1; then
    echo "Accepted invalid version: $invalid" >&2; exit 1
  fi
done
echo 'Release policy: 11 cases passed.'
