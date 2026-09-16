#!/usr/bin/env bash
# Single mapping shared by release builds and tests. Stable defaults stay on 8.3.
set -euo pipefail
version=${1:?usage: image-runtime.sh VERSION [auto|83|84]}
runtime=${2:-auto}
if [[ "$runtime" == auto ]]; then
  case "$version" in
    v5.3.*-beta*|v5.3.*-rc*) runtime=84 ;;
    *) runtime=83 ;;
  esac
fi
case "$version:$runtime" in v4.*:84) echo 'Moodle 4.x requires PHP 8.3' >&2; exit 1 ;; esac
case "$runtime" in
  83) base=3.20 ;;
  84) base=3.23 ;;
  *) echo "Unsupported PHP runtime: $runtime" >&2; exit 1 ;;
esac
printf 'php=%s\nbase=%s\n' "$runtime" "$base"
