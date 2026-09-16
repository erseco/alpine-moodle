#!/usr/bin/env bash
# Resolve publication policy; only --newest contacts upstream.
set -euo pipefail
version=${1:?usage: release-policy.sh VERSION [NEWEST_STABLE_TAG] | --newest}
# Deliberately selected production line; change only in the LTS promotion PR.
stable_pattern='^v5[.]2[.][0-9]+$'
if [[ "$version" == --newest ]]; then
  git ls-remote --tags --refs https://github.com/moodle/moodle.git \
    | awk -v pattern="$stable_pattern" '{sub("refs/tags/", "", $2); if ($2 ~ pattern) print $2}' \
    | sort -V | tail -1
  exit 0
fi
newest=${2:-}
case "$version" in
  main) ;;
  *) [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]*|-rc[0-9]+)?$ ]] || {
    echo "Invalid Moodle version: $version" >&2; exit 1;
  } ;;
esac
latest=false
if [[ "$version" =~ $stable_pattern && "$version" == "$newest" ]]; then
  latest=true
fi
printf 'version=%s\nlatest=%s\n' "$version" "$latest"
