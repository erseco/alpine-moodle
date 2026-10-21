#!/usr/bin/env bash
# Single mapping shared by release builds and tests. Preserve legacy tag runtimes.
set -euo pipefail
version=${1:?usage: image-runtime.sh VERSION [auto|83|84]}
runtime=${2:-auto}
if [[ "$runtime" == auto ]]; then
  case "$version" in
    v4.*|v5.0.*|v5.1.*|v5.2.*) runtime=83 ;;
    *) runtime=84 ;;
  esac
fi
case "$version:$runtime" in v4.*:84) echo 'Moodle 4.x requires PHP 8.3' >&2; exit 1 ;; esac
case "$runtime" in
  # PHP 8.3 and 8.4 come from the alpine-php-webserver -php83/-php84 variants
  # on Alpine 3.24: 3.20 is EOL and 3.23 lags on PHP security releases (#180).
  83) base=3.24-php83 ;;
  84) base=3.24-php84 ;;
  *) echo "Unsupported PHP runtime: $runtime" >&2; exit 1 ;;
esac
printf 'php=%s\nbase=%s\n' "$runtime" "$base"
