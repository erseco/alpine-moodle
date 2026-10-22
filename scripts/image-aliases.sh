#!/usr/bin/env bash
# Plain-number image tags derived from the vX.Y.Z release tags (git tags, one per line on stdin).
#   image-aliases.sh plan            "<release tag> <alias>" per alias: X.Y.Z for every release,
#                                    plus X.Y and X for the newest stable release of each series
#                                    (X.Y-php84 for the opt-in PHP 8.4 line)
#   image-aliases.sh readme [LATEST] markdown list with the newest release of each series and its tags
set -euo pipefail
cd "$(dirname "$0")/.."
min_series=4.5 # older series are no longer built

at_least() { [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1) == "$2" ]]; }

# Release tags of the supported series: stable, -php84, beta and RC
releases() {
  local tag minor
  grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]*|-rc[0-9]+|-php84)?$' | while read -r tag; do
    minor=$(cut -d. -f1,2 <<< "${tag#v}")
    if at_least "$minor" "$min_series"; then echo "$tag"; fi
  done
}

plan() {
  local all tag suffix stable
  all=$(releases)
  for tag in $all; do echo "$tag ${tag#v}"; done
  for suffix in '' -php84; do
    stable=$(grep -E "^v[0-9]+\.[0-9]+\.[0-9]+$suffix\$" <<< "$all" | sort -V) || continue
    # Ascending order: the last release seen in a series is its newest.
    awk -v suffix="$suffix" '{
      split(substr($1, 2), v, /[.-]/)
      minor[v[1] "." v[2]] = $1; major[v[1]] = $1
    } END {
      for (s in minor) print minor[s], s suffix
      # X-php84 would be misleading: unsuffixed X is already PHP 8.4 since 5.3.
      if (suffix == "") for (s in major) print major[s], s
    }' <<< "$stable"
  done
}

# "`<tag>`, `<alias>`, ... (PHP X.Y)" for release $1
entry() {
  local tags="\`$1\`" alias php
  for alias in $(awk -v tag="$1" '$1 == tag {print $2}' <<< "$aliases"); do tags+=", \`$alias\`"; done
  [[ $1 != "$latest" ]] || tags+=', `latest`'
  if [[ $1 == *-php84 ]]; then
    php=$(bash scripts/image-runtime.sh "${1%-php84}" 84)
  else
    php=$(bash scripts/image-runtime.sh "$1")
  fi
  php=$(sed -n 's/^php=//p' <<< "$php")
  echo "$tags (PHP ${php:0:1}.${php:1})"
}

readme() {
  local latest=${1:-} aliases release line php84
  aliases=$(plan)
  for release in $(awk '$2 ~ /^[0-9]+\.[0-9]+$/ {print $1}' <<< "$aliases" | sort -Vr); do
    line=$(entry "$release")
    php84=$(awk -v alias="$(cut -d. -f1,2 <<< "${release#v}")-php84" '$2 == alias {print $1}' <<< "$aliases")
    [[ -z $php84 ]] || line+=" · $(entry "$php84")"
    echo "- $line"
  done
}

case "${1:-}" in
  plan | readme) "$@" ;;
  *) echo 'usage: image-aliases.sh plan | readme [LATEST]' >&2; exit 1 ;;
esac
