#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
log=$(mktemp)
trap 'rm -f "$log"' EXIT
export log DOCKER_USERNAME=hubuser DOCKER_PASSWORD=hubpass GHCR_USERNAME=ghuser GHCR_TOKEN=ghpass
export index='{"schemaVersion":2,"manifests":[]}'
a=sha256:$(printf '%s' "$index" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1)
b=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export a b
# Docker Hub: v5.2.4 published, 5.2.4 already on it, 5.2 still on an older digest; two pages.
# GHCR: only v5.2.4 is published, no aliases yet. Docker Hub manifests are never read.
curl() {
  local args="$*" out='' headers='' url=${*: -1}
  while (($#)); do
    case "$1" in -o) out=$2; shift ;; -D) headers=$2; shift ;; esac
    shift
  done
  case "$args" in
    *'-X PUT'*)
      printf 'PUT %s %s\n' "$url" "$(grep -o 'Content-Type: [^ ]*' <<< "$args")" >> "$log"
      [[ "${fail_put:-false}" == false ]] ;;
    *'-u ghuser:ghpass https://ghcr.io/token'*|*'-u hubuser:hubpass https://auth.docker.io/token'*) echo '{"token":"t"}' ;;
    *token*) return 22 ;;
    *'-fsSI -H Authorization: Bearer t'*/manifests/v5.2.4)
      printf 'HEAD %s\n' "$url" >> "$log"; printf 'HTTP/2 200\r\ndocker-content-digest: %s\r\n' "$a" ;;
    *-fsSI*) printf 'HEAD %s\n' "$url" >> "$log"; return 22 ;;
    *"https://ghcr.io/v2/example/moodle/manifests/$a")
      printf 'GET %s\n' "$url" >> "$log"
      printf '%s' "$index" > "$out"
      printf 'HTTP/2 200\r\ncontent-type: application/vnd.oci.image.index.v1+json\r\n' > "$headers" ;;
    *registry-1.docker.io*) printf 'GET %s\n' "$url" >> "$log"; return 22 ;;
    *page=2*) echo '{"next":null,"results":[{"name":"5.2","digest":"'"$b"'"}]}' ;;
    *hub.docker.com*) echo '{"next":"https://hub.docker.com/v2/x?page=2","results":[{"name":"v5.2.4","digest":"'"$a"'"},{"name":"5.2.4","digest":"'"$a"'"}]}' ;;
    *) echo "unexpected curl $args" >&2; return 1 ;;
  esac
}
export -f curl
plan='v5.2.4 5.2.4
v5.2.4 5.2
v5.2.5 5.2.5'
bash scripts/sync-image-aliases.sh example/moodle <<< "$plan" > /dev/null
puts=$(grep '^PUT' "$log")
type='Content-Type: application/vnd.oci.image.index.v1+json'
expected="PUT https://registry-1.docker.io/v2/example/moodle/manifests/5.2 $type
PUT https://ghcr.io/v2/example/moodle/manifests/5.2.4 $type
PUT https://ghcr.io/v2/example/moodle/manifests/5.2 $type"
[[ "$puts" == "$expected" ]] || { diff <(echo "$expected") <(echo "$puts") >&2; exit 1; }
# The index is read once, from GHCR, and Docker Hub manifests are never pulled.
[[ $(grep -c '^GET' "$log") -eq 1 ]]
# Each GHCR tag is inspected once, however many aliases share the release.
[[ $(grep -c '^HEAD .*manifests/v5.2.4$' "$log") -eq 1 ]]
must_fail() {
  if bash scripts/sync-image-aliases.sh "$1" <<< "$2" > /dev/null 2>&1; then
    echo "Expected failure: $1 / $2" >&2; exit 1
  fi
}
must_fail 'example/moodle;id' "$plan"
must_fail example/moodle 'v5.2.4 5.2;id'
must_fail example/moodle 'latest 5.2'
# An index whose body does not match its digest is never written.
: > "$log"
index=tampered must_fail example/moodle "$plan"
! grep -q '^PUT' "$log" || { echo 'Wrote a tampered index' >&2; exit 1; }
export fail_put=true
must_fail example/moodle "$plan"
echo 'Sync image aliases: all cases passed.'
