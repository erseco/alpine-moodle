#!/usr/bin/env sh
#
# tests/verify-moodle-version.sh IMAGE EXPECTED
#
# Release gate for #161: refuse to publish an image whose baked-in Moodle
# code does not match the git tag being built.
#
#   IMAGE     local docker image to inspect
#   EXPECTED  vX.Y.Z git tag, or "main" for main-branch snapshots
#
# Stable tags (vX.Y.Z) must match version.php's $release exactly
# ("X.Y.Z (Build: ...)" — a weekly "X.Y.Z+" does NOT pass). Pre-release tags
# (v5.2.0-rc1, v5.2.0-beta) and main only require a parseable release, since
# upstream's pre-release $release strings ("5.2rc1") don't map 1:1 to tag
# names.
set -eu

IMAGE="${1:?usage: verify-moodle-version.sh IMAGE vX.Y.Z|main}"
EXPECTED="${2:?usage: verify-moodle-version.sh IMAGE vX.Y.Z|main}"

# Moodle <5.1 keeps version.php at the tree root; 5.1+ moved it under public/.
version_php=$(docker run --rm --entrypoint sh "$IMAGE" -c \
  'cat /var/www/html/public/version.php /var/www/html/version.php 2>/dev/null || true')

release_line=$(printf '%s\n' "$version_php" \
  | grep -E '^[[:space:]]*\$release[[:space:]]*=' | head -n 1 || true)
release=${release_line#*\'}
release=${release%%\'*}

if [ -z "$release" ] || [ "$release" = "$release_line" ]; then
  echo "ERROR: could not read \$release from version.php in $IMAGE" >&2
  exit 1
fi
echo "Image $IMAGE contains Moodle release: $release"

case "$EXPECTED" in
  main|*-rc*|*-beta*)
    echo "OK: no strict release match required for '$EXPECTED' builds."
    ;;
  v*.*.*)
    want="${EXPECTED#v}"
    case "$release" in
      "$want"|"$want "*)
        echo "OK: release matches tag $EXPECTED."
        ;;
      *)
        echo "ERROR: image Moodle release '$release' does not match tag $EXPECTED" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "ERROR: unrecognised expected version '$EXPECTED' (want vX.Y.Z or main)" >&2
    exit 1
    ;;
esac
