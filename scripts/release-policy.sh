#!/usr/bin/env bash
# Resolve the requested upstream version and publication policy (no network).
set -euo pipefail
version=${1:?usage: release-policy.sh VERSION [NEWEST_STABLE_TAG]}
newest=${2:-}
case "$version" in
  main) ;;
  *) [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]*|-rc[0-9]+)?$ ]] || {
    echo "Invalid Moodle version: $version" >&2; exit 1;
  } ;;
esac
# Deliberately selected production line; change only in the LTS promotion PR.
latest=false
if [[ "$version" =~ ^v5\.2\.[0-9]+$ && "$version" == "$newest" ]]; then
  latest=true
fi
printf 'version=%s\nlatest=%s\n' "$version" "$latest"
