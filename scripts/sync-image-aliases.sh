#!/usr/bin/env bash
# Point every alias of the plan on stdin ("<release tag> <alias>" lines, from
# image-aliases.sh plan) at the exact multi-arch index of its release, on Docker Hub
# and GHCR. Idempotent: aliases already on the right digest are left alone, and
# releases not published yet (build still running or failed) are skipped.
#
# Talks to the registry API directly: the index of a release has the same digest,
# so the same bytes, on both registries, so it is read from GHCR and PUT under each
# alias. Copying with imagetools pulls every platform manifest from Docker Hub and
# hits its pull rate limit after a few dozen aliases.
#
# Credentials: DOCKER_USERNAME/DOCKER_PASSWORD (Docker Hub), GHCR_USERNAME/GHCR_TOKEN.
set -euo pipefail
repository=${1:?usage: sync-image-aliases.sh REPOSITORY < plan}
[[ "$repository" =~ ^[a-z0-9_-]+/[a-z0-9_.-]+$ ]] || { echo 'Invalid repository' >&2; exit 1; }
plan=$(cat)
index_types='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sha256() { if command -v sha256sum > /dev/null; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }

# "<tag> <digest>" of every Docker Hub tag. The Hub API does not count against pull limits.
hub_digests() {
  local url="https://hub.docker.com/v2/repositories/$repository/tags?page_size=100" page
  while [[ -n $url && $url != null ]]; do
    page=$(curl -fsS "$url")
    jq -r '.results[] | "\(.name) \(.digest // "")"' <<< "$page"
    url=$(jq -r .next <<< "$page")
  done
}

# Registry API host of image $1, and a pull/push token for it. Docker Hub tokens
# last five minutes, so one is requested for every request.
api() { if [[ $1 == ghcr.io/* ]]; then echo ghcr.io; else echo registry-1.docker.io; fi; }
token() {
  if [[ $1 == ghcr.io/* ]]; then
    curl -fsS -u "$GHCR_USERNAME:$GHCR_TOKEN" "https://ghcr.io/token?service=ghcr.io&scope=repository:$repository:pull,push"
  else
    curl -fsS -u "$DOCKER_USERNAME:$DOCKER_PASSWORD" \
      "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repository:pull,push"
  fi | jq -r .token
}

# Digest of GHCR tag $1 from a HEAD request (empty when missing)
ghcr_digest() {
  curl -fsSI -H "Authorization: Bearer $ghcr_token" -H "Accept: $index_types" \
    "https://ghcr.io/v2/$repository/manifests/$1" 2>/dev/null \
    | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" {print $2}' || true
}

# Sets $found to the digest of $1:$2 (empty when missing). Results are cached in
# $known ("<image:tag> <digest>" lines) so each GHCR tag is inspected once.
known=
lookup() {
  local key="$1:$2"
  if found=$(awk -v key="$key" '$1 == key {print $2; hit = 1; exit} END {exit !hit}' <<< "$known"); then
    return
  fi
  if [[ $1 == ghcr.io/* ]]; then
    found=$(ghcr_digest "$2")
  else
    found=$(awk -v tag="$2" '$1 == tag {print $2}' <<< "$hub")
  fi
  known+="$key $found"$'\n'
}

# Saves index $1 to $work/$1 and its media type to $work/$1.type, from GHCR or, when
# GHCR lacks it, from image $2. The body must hash to $1, so it is the exact index.
fetch_index() {
  local source
  [[ ! -s "$work/$1" ]] || return 0
  for source in "ghcr.io/$repository" "$2"; do
    if curl -fsS -H "Authorization: Bearer $(token "$source")" -H "Accept: $index_types" \
      -D "$work/$1.headers" -o "$work/$1" "https://$(api "$source")/v2/$repository/manifests/$1" 2>/dev/null \
      && [[ "sha256:$(sha256 < "$work/$1")" == "$1" ]]; then
      tr -d '\r' < "$work/$1.headers" | awk 'tolower($1) == "content-type:" {print $2}' > "$work/$1.type"
      return 0
    fi
  done
  rm -f "$work/$1"
  return 1
}

tag() { # $1 image, $2 alias, $3 digest
  fetch_index "$3" "$1" && curl -fsS -o /dev/null -X PUT \
    -H "Authorization: Bearer $(token "$1")" -H "Content-Type: $(cat "$work/$3.type")" \
    --data-binary "@$work/$3" "https://$(api "$1")/v2/$repository/manifests/$2"
}

hub=$(hub_digests)
ghcr_token=$(token "ghcr.io/$repository")
failed=0
for image in "$repository" "ghcr.io/$repository"; do
  # fd 3, so no command in the loop can swallow the plan from stdin
  while read -r release alias <&3; do
    [[ -n $release ]] || continue
    [[ $release =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)?$ && $alias =~ ^[0-9]+(\.[0-9]+)*(-[a-z0-9]+)?$ ]] || {
      echo "Invalid plan line: $release $alias" >&2; exit 1;
    }
    lookup "$image" "$release"
    source=$found
    if [[ ! $source =~ ^sha256:[a-f0-9]{64}$ ]]; then
      echo "Skip $image:$alias: $release is not published"
      continue
    fi
    lookup "$image" "$alias"
    [[ $found != "$source" ]] || continue
    echo "$image:$alias -> $release ($source)"
    if tag "$image" "$alias" "$source"; then
      known+="$image:$alias $source"$'\n'
    else
      echo "::warning::Could not tag $image:$alias" >&2
      failed=1
    fi
  done 3<<< "$plan"
done
exit "$failed"
