#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
log=$(mktemp)
trap 'rm -f "$log"' EXIT
export log
a=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
b=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export a b
# Docker Hub: v5.2.4 published, 5.2.4 already on it, 5.2 still on an older digest; two pages.
# GHCR: only v5.2.4 is published, no aliases yet.
curl() {
  printf 'curl %s\n' "$*" >> "$log"
  case "$*" in
    *ghcr.io/token*) echo '{"token":"t"}' ;;
    *'Bearer t'*/manifests/v5.2.4) printf 'HTTP/2 200\r\ndocker-content-digest: %s\r\n' "$a" ;;
    *ghcr.io*) return 22 ;;
    *page=2*) echo '{"next":null,"results":[{"name":"5.2","digest":"'"$b"'"}]}' ;;
    *) echo '{"next":"https://hub.docker.com/v2/x?page=2","results":[{"name":"v5.2.4","digest":"'"$a"'"},{"name":"5.2.4","digest":"'"$a"'"}]}' ;;
  esac
}
docker() { printf '%s\n' "$*" >> "$log"; [[ "${fail_docker:-false}" == false ]]; }
export -f curl docker
plan='v5.2.4 5.2.4
v5.2.4 5.2
v5.2.5 5.2.5'
bash scripts/sync-image-aliases.sh example/moodle <<< "$plan" > /dev/null
creates=$(grep 'imagetools create' "$log")
expected="buildx imagetools create --prefer-index=false --tag example/moodle:5.2 example/moodle@$a
buildx imagetools create --prefer-index=false --tag ghcr.io/example/moodle:5.2.4 ghcr.io/example/moodle@$a
buildx imagetools create --prefer-index=false --tag ghcr.io/example/moodle:5.2 ghcr.io/example/moodle@$a"
[[ "$creates" == "$expected" ]] || { diff <(echo "$expected") <(echo "$creates") >&2; exit 1; }
# Each GHCR tag is inspected once, however many aliases share the release.
[[ $(grep -c 'manifests/v5.2.4$' "$log") -eq 1 ]]
must_fail() {
  if bash scripts/sync-image-aliases.sh "$1" <<< "$2" > /dev/null 2>&1; then
    echo "Expected failure: $1 / $2" >&2; exit 1
  fi
}
must_fail 'example/moodle;id' "$plan"
must_fail example/moodle 'v5.2.4 5.2;id'
must_fail example/moodle 'latest 5.2'
export fail_docker=true
must_fail example/moodle "$plan"
echo 'Sync image aliases: all cases passed.'
