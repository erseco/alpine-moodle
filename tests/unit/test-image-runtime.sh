#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
all=linux/amd64,linux/arm64,linux/ppc64le,linux/s390x
check() {
  [[ "$(bash scripts/image-runtime.sh "$1" "$2")" == "php=$3"$'\n'"base=$4"$'\n'"stage=$5"$'\n'"platforms=$6" ]]
}
# Moodle 4.1 refuses PHP >= 8.2, so it gets PHP 8.1 compiled from the patched
# php-src branch (#189) on the 3.24-php83 webserver layout, amd64/arm64 only.
check v4.1.22 auto 81 3.24-php83 php81 linux/amd64,linux/arm64
check v4.1.22 81 81 3.24-php83 php81 linux/amd64,linux/arm64
check v4.5.14 auto 83 3.24-php83 webserver "$all"
check v5.0.10 auto 83 3.24-php83 webserver "$all"
check v5.1.7 auto 83 3.24-php83 webserver "$all"
check v5.2.3 auto 83 3.24-php83 webserver "$all"
check v5.3.0-beta auto 84 3.24-php84 webserver "$all"
check v5.3.0-beta1 auto 84 3.24-php84 webserver "$all"
check v5.3.0-beta2 auto 84 3.24-php84 webserver "$all"
check v5.3.0-rc1 auto 84 3.24-php84 webserver "$all"
check v5.3.0-rc2 auto 84 3.24-php84 webserver "$all"
check v5.3.0-rc10 auto 84 3.24-php84 webserver "$all"
check v5.3.0 auto 84 3.24-php84 webserver "$all"
check main auto 84 3.24-php84 webserver "$all"
check main 84 84 3.24-php84 webserver "$all"
check v5.2.3 84 84 3.24-php84 webserver "$all"
if bash scripts/image-runtime.sh v4.5.14 84; then exit 1; fi
if bash scripts/image-runtime.sh v4.1.22 83; then exit 1; fi
if bash scripts/image-runtime.sh v4.1.22 84; then exit 1; fi
if bash scripts/image-runtime.sh v4.5.14 81; then exit 1; fi
if bash scripts/image-runtime.sh main 85; then exit 1; fi
echo 'Runtime policy: 23 cases passed.'
