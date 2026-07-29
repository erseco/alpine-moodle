#!/bin/sh
# Create and push -php84 Git tags for Moodle 5.x releases.
#
# Each tag is created on the CURRENT commit of the local `php84` branch, so the
# PHP 8.4 Dockerfile and the build-php84 workflow are present in the tagged
# commit. Pushing a vX.Y.Z-php84 tag triggers .github/workflows/build-php84.yml,
# which publishes:
#   erseco/alpine-moodle:vX.Y.Z-php84
#   ghcr.io/erseco/alpine-moodle:vX.Y.Z-php84
#
# Usage:
#   scripts/build-php84-tags.sh v5.0.8 v5.1.5 v5.2.1
#
# Environment overrides:
#   REMOTE   git remote to push to   (default: origin)
#   BRANCH   branch tags must be on  (default: php84)
#
# POSIX sh; only Moodle 5.x and later versions (vX where X >= 5) are accepted.
set -eu

REMOTE="${REMOTE:-origin}"
BRANCH="${BRANCH:-php84}"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <moodle-version>...   (e.g. $0 v5.0.8 v5.1.5 v5.2.1)" >&2
  exit 1
fi

# Tags must point at the php84 branch commit, so refuse to run elsewhere.
current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$current_branch" != "$BRANCH" ]; then
  echo "ERROR: expected to be on the '$BRANCH' branch, but on '$current_branch'." >&2
  echo "       Run: git checkout $BRANCH" >&2
  exit 1
fi

# Validate every argument up front before creating any tag.
for version in "$@"; do
  case "$version" in
    v5.*) : ;;
    *)
      echo "ERROR: '$version' is not a Moodle 5.x version (must start with 'v5.')." >&2
      echo "       PHP 8.4 images are only published for Moodle 5.x and later." >&2
      exit 1
      ;;
  esac
done

for version in "$@"; do
  tag="${version}-php84"
  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
    echo "Tag ${tag} already exists locally, skipping creation."
  else
    echo "Creating tag ${tag} at $(git rev-parse --short HEAD) (${BRANCH})"
    git tag "${tag}"
  fi
  echo "Pushing ${tag} to ${REMOTE}"
  git push "${REMOTE}" "${tag}"
done

echo "Done. The build-php84 workflow will publish the -php84 images for the pushed tags."
