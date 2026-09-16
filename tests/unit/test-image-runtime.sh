#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check() {
  [[ "$(bash scripts/image-runtime.sh "$1" "$2")" == "php=$3"$'\n'"base=$4" ]]
}
check v4.5.14 auto 83 3.20
check v5.2.3 auto 83 3.20
check v5.3.0-beta auto 84 3.23
check v5.3.0-rc1 auto 84 3.23
check v5.3.0 auto 84 3.23
check main auto 84 3.23
check main 84 84 3.23
check v5.2.3 84 84 3.23
if bash scripts/image-runtime.sh v4.5.14 84; then exit 1; fi
if bash scripts/image-runtime.sh main 85; then exit 1; fi
echo 'Runtime policy: 10 cases passed.'
