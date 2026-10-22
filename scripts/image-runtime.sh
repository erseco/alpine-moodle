#!/usr/bin/env bash
# Single mapping shared by release builds and tests. Preserve legacy tag runtimes.
set -euo pipefail
version=${1:?usage: image-runtime.sh VERSION [auto|81|83|84]}
runtime=${2:-auto}
if [[ "$runtime" == auto ]]; then
  case "$version" in
    v4.1.*) runtime=81 ;;
    v4.*|v5.0.*|v5.1.*|v5.2.*) runtime=83 ;;
    *) runtime=84 ;;
  esac
fi
case "$version:$runtime" in
  v4.1.*:81) ;;
  # Moodle 4.1 refuses PHP >= 8.2 (restrict_php_version_82 in environment.xml).
  v4.1.*:*|*:81) echo 'PHP 8.1 is only built for Moodle 4.1' >&2; exit 1 ;;
  v4.*:84) echo 'Moodle 4.x requires PHP 8.3' >&2; exit 1 ;;
esac
stage=webserver
platforms=linux/amd64,linux/arm64,linux/ppc64le,linux/s390x
case "$runtime" in
  # PHP 8.1 is EOL and no longer packaged by Alpine: the Dockerfile's php81
  # stage compiles it from the php-src branch with the CVE-2026-109618/109619
  # backport (#189) on top of the 3.24-php83 webserver layout. Compiling under
  # QEMU is slow, so only amd64 and arm64 are published.
  81) base=3.24-php83 stage=php81 platforms=linux/amd64,linux/arm64 ;;
  # PHP 8.3 and 8.4 come from the alpine-php-webserver -php83/-php84 variants
  # on Alpine 3.24: 3.20 is EOL and 3.23 lags on PHP security releases (#180).
  83) base=3.24-php83 ;;
  84) base=3.24-php84 ;;
  *) echo "Unsupported PHP runtime: $runtime" >&2; exit 1 ;;
esac
printf 'php=%s\nbase=%s\nstage=%s\nplatforms=%s\n' "$runtime" "$base" "$stage" "$platforms"
