#!/usr/bin/env bash
# Point every alias of the plan on stdin ("<release tag> <alias>" lines, from
# image-aliases.sh plan) at the exact multi-arch index of its release, on Docker Hub
# and GHCR. Idempotent: aliases already on the right digest are left alone, and
# releases not published yet (build still running or failed) are skipped.
set -euo pipefail
repository=${1:?usage: sync-image-aliases.sh REPOSITORY < plan}
[[ "$repository" =~ ^[a-z0-9_-]+/[a-z0-9_.-]+$ ]] || { echo 'Invalid repository' >&2; exit 1; }
plan=$(cat)

# "<tag> <digest>" of every Docker Hub tag. The Hub API does not count against pull limits.
hub_digests() {
  local url="https://hub.docker.com/v2/repositories/$repository/tags?page_size=100" page
  while [[ -n $url && $url != null ]]; do
    page=$(curl -fsS "$url")
    jq -r '.results[] | "\(.name) \(.digest // "")"' <<< "$page"
    url=$(jq -r .next <<< "$page")
  done
}

# Digest of GHCR tag $1 from a HEAD request (empty when missing): much faster than
# imagetools inspect, and the index digest is the same one Docker Hub reports.
ghcr_digest() {
  curl -fsSI -H "Authorization: Bearer $ghcr_token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
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

hub=$(hub_digests)
ghcr_token=$(curl -fsS "https://ghcr.io/token?scope=repository:$repository:pull" | jq -r .token)
failed=0
for image in "$repository" "ghcr.io/$repository"; do
  # fd 3, so docker cannot swallow the plan from stdin
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
    if docker buildx imagetools create --prefer-index=false --tag "$image:$alias" "$image@$source"; then
      known+="$image:$alias $source"$'\n'
    else
      echo "::warning::Could not tag $image:$alias" >&2
      failed=1
    fi
  done 3<<< "$plan"
done
exit "$failed"
