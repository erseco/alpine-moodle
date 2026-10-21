#!/usr/bin/env bash
# Caller must hold the workflow's latest-promotion concurrency lock.
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:?usage: promote-latest.sh VERSION DIGEST REPOSITORY}
digest=${2:?missing image digest}
repository=${3:?missing image repository}
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid digest' >&2; exit 1; }
[[ "$repository" =~ ^[a-z0-9_-]+/[a-z0-9_.-]+$ ]] || { echo 'Invalid repository' >&2; exit 1; }
newest=$(bash scripts/release-policy.sh --newest)
policy=$(bash scripts/release-policy.sh "$version" "$newest")
if ! grep -qx 'latest=true' <<< "$policy"; then
  echo "Skip latest: $version is not the current stable release ($newest)."
  exit 0
fi
# Copy the tested manifest index, preserving every architecture and its digest.
# Registry writes are not atomic together: rerun a failed job to reconcile both.
for image in "$repository" "ghcr.io/$repository"; do
  docker buildx imagetools create --prefer-index=false --tag "$image:latest" "$image@$digest"
done
