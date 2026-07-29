#!/bin/sh
#
# 010-sync-moodle-code.sh
#
# Version-aware Moodle core sync for persistent /var/www/html volumes (#103).
#
# When /var/www/html is a named volume, Docker only seeds it on first use from
# the image. Later image upgrades (v5.0.1 → v5.0.2) leave the volume on the old
# tree, so AUTO_UPDATE_MOODLE runs upgrade.php against stale code.
#
# This script mirrors the official Moodle upgrade step "replace the code while
# keeping config.php" by rsyncing the immutable tree baked into the image at
# /usr/src/moodle into /var/www/html when versions diverge.
#
# Environment:
#   SYNC_MOODLE_CODE      auto|always|never  (default: auto)
#   SYNC_PRESERVE_PLUGINS true|false (default: true). When true, directories
#                         containing a version.php that do not exist in the
#                         image tree (i.e. third-party plugins installed into
#                         the volume) are preserved across the sync, matching
#                         Moodle's official upgrade procedure of carrying
#                         custom plugins over to the new code tree.
#   EXTRA_PLUGIN_PATHS    space-separated relative paths under html to preserve
#                         (e.g. "mod/attendance theme/space local/foo").
#                         Still useful for custom paths without a version.php.
#   MOODLE_SRC_DIR        override source tree (default: /usr/src/moodle)
#   MOODLE_HTML_DIR       override runtime tree (default: /var/www/html)
#
# When the image and volume use different layouts (Moodle moved the web root
# under public/ in 5.1), preserved paths are relocated to match the image
# layout, e.g. mod/attendance → public/mod/attendance.
#
# Stamp file written after a successful sync:
#   $MOODLE_HTML_DIR/.alpine-moodle-release  (Moodle $version id from version.php)
#
set -eu

MOODLE_SRC_DIR="${MOODLE_SRC_DIR:-/usr/src/moodle}"
MOODLE_HTML_DIR="${MOODLE_HTML_DIR:-/var/www/html}"
STAMP_NAME=".alpine-moodle-release"
STAMP_FILE="${MOODLE_HTML_DIR}/${STAMP_NAME}"
SYNC_MODE="${SYNC_MOODLE_CODE:-auto}"
PRESERVE_PLUGINS="${SYNC_PRESERVE_PLUGINS:-true}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Resolve the path to Moodle's root version.php.
# Pre-5.1: <root>/version.php
# 5.1+:    <root>/public/version.php  (web root moved under public/)
moodle_version_php() {
  root="$1"
  if [ -f "${root}/version.php" ]; then
    printf '%s\n' "${root}/version.php"
  elif [ -f "${root}/public/version.php" ]; then
    printf '%s\n' "${root}/public/version.php"
  fi
}

# Extract Moodle $version (e.g. 2025041401.00) from a Moodle tree root.
# Prints empty string if unparseable.
moodle_version_id() {
  root="$1"
  version_php="$(moodle_version_php "$root")"
  if [ -z "$version_php" ] || [ ! -f "$version_php" ]; then
    return 0
  fi
  # Match: $version  = 2025041401.00;  (allow flexible whitespace)
  sed -n 's/^[[:space:]]*\$version[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
    "$version_php" | head -n 1
}

moodle_tree_present() {
  root="$1"
  if [ -f "${root}/version.php" ] || [ -f "${root}/public/version.php" ] \
    || [ -f "${root}/lib/moodlelib.php" ] || [ -f "${root}/public/lib/moodlelib.php" ]; then
    return 0
  fi
  return 1
}

# Translate a volume-relative path into the image tree's layout. Moodle 5.1
# moved the web root under public/; a plugin preserved from a pre-5.1 volume
# must be restored under public/ (and vice versa) or Moodle will not see it.
# Uses $src_has_public, set in main before any call.
translate_layout_path() {
  tl_rel="$1"
  if [ "$src_has_public" = "yes" ]; then
    case "$tl_rel" in
      public|public/*) printf '%s\n' "$tl_rel" ;;
      *) printf 'public/%s\n' "$tl_rel" ;;
    esac
  else
    case "$tl_rel" in
      public/*) printf '%s\n' "${tl_rel#public/}" ;;
      *) printf '%s\n' "$tl_rel" ;;
    esac
  fi
}

# Paths that must never be auto-preserved as third-party plugins even when a
# file called version.php exists inside them (composer/npm packages etc.).
is_ignored_plugin_dir() {
  case "$1" in
    vendor|vendor/*|public/vendor|public/vendor/*) return 0 ;;
    node_modules|node_modules/*|*/node_modules|*/node_modules/*) return 0 ;;
    .git|.git/*|*/.git|*/.git/*) return 0 ;;
  esac
  return 1
}

# Validate EXTRA_PLUGIN_PATHS entries: relative, no .., no absolute.
validate_extra_path() {
  relpath="$1"
  case "$relpath" in
    ""|.*|/*|*..*|*../*|*/../*|*/..)
      echo "ERROR: invalid EXTRA_PLUGIN_PATHS entry: '$relpath'" >&2
      echo "       Paths must be relative to the Moodle root (e.g. mod/attendance)." >&2
      return 1
      ;;
  esac
  return 0
}

should_sync() {
  mode="$1"
  image_ver="$2"
  volume_ver="$3"
  html_has_code="$4"

  case "$mode" in
    never)
      return 1
      ;;
    always)
      return 0
      ;;
    auto|"")
      # Empty volume / missing code → always seed from the image.
      if [ "$html_has_code" != "yes" ]; then
        return 0
      fi
      # Missing image version is fatal only if we would sync; handled by caller.
      if [ -z "$volume_ver" ] || [ "$volume_ver" != "$image_ver" ]; then
        return 0
      fi
      return 1
      ;;
    *)
      echo "ERROR: SYNC_MOODLE_CODE must be auto|always|never (got '$mode')" >&2
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [ ! -d "$MOODLE_SRC_DIR" ] || ! moodle_tree_present "$MOODLE_SRC_DIR"; then
  echo "WARNING: Moodle source tree missing at ${MOODLE_SRC_DIR}; skipping code sync."
  exit 0
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync is required for Moodle code sync but was not found." >&2
  exit 1
fi

case "$PRESERVE_PLUGINS" in
  true|false) ;;
  *)
    echo "ERROR: SYNC_PRESERVE_PLUGINS must be true|false (got '$PRESERVE_PLUGINS')" >&2
    exit 1
    ;;
esac

image_ver="$(moodle_version_id "$MOODLE_SRC_DIR")"
if [ -z "$image_ver" ]; then
  echo "ERROR: could not parse \$version from ${MOODLE_SRC_DIR} (version.php)" >&2
  exit 1
fi

src_has_public=no
if [ -d "${MOODLE_SRC_DIR}/public" ]; then
  src_has_public=yes
fi

volume_ver=""
if [ -f "$STAMP_FILE" ] && [ -s "$STAMP_FILE" ]; then
  volume_ver="$(tr -d '[:space:]' < "$STAMP_FILE")"
else
  volume_ver="$(moodle_version_id "$MOODLE_HTML_DIR")"
fi

html_has_code="no"
if moodle_tree_present "$MOODLE_HTML_DIR"; then
  html_has_code="yes"
fi

if ! should_sync "$SYNC_MODE" "$image_ver" "$volume_ver" "$html_has_code"; then
  echo "Moodle code sync: skipped (SYNC_MOODLE_CODE=${SYNC_MODE}, image=${image_ver}, volume=${volume_ver:-<none>})."
  exit 0
fi

echo "Moodle code sync: ${volume_ver:-<empty|unknown>} → ${image_ver} (mode=${SYNC_MODE})"

tmpdir="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'rm -rf "$tmpdir"' EXIT

# 1) Preserve config.php
if [ -f "${MOODLE_HTML_DIR}/config.php" ]; then
  cp -a "${MOODLE_HTML_DIR}/config.php" "${tmpdir}/config.php"
  echo "  preserved config.php"
fi

# 2) Preserve EXTRA_PLUGIN_PATHS
# shellcheck disable=SC2086
for relpath in ${EXTRA_PLUGIN_PATHS:-}; do
  validate_extra_path "$relpath"
  src="${MOODLE_HTML_DIR}/${relpath}"
  if [ -e "$src" ]; then
    mkdir -p "${tmpdir}/extra/$(dirname "$relpath")"
    cp -a "$src" "${tmpdir}/extra/${relpath}"
    echo "  preserved ${relpath}"
  else
    echo "  EXTRA_PLUGIN_PATHS: ${relpath} not present (skip)"
  fi
done

# 2b) Auto-preserve third-party plugins: any directory with a version.php that
#     has no counterpart in the image tree was installed by the user (web
#     installer, manual copy) and must survive the sync — Moodle's official
#     upgrade procedure carries custom plugins over to the new code tree.
#     The counterpart check uses the layout-translated path so that core
#     plugins of a pre-5.1 volume (mod/forum → public/mod/forum) are not
#     misdetected as third-party during a public/-layout upgrade.
: > "${tmpdir}/auto-paths"
if [ "$PRESERVE_PLUGINS" = "true" ] && [ "$html_has_code" = "yes" ]; then
  find "$MOODLE_HTML_DIR" -mindepth 2 -maxdepth 8 -type f -name version.php 2>/dev/null \
    | sort > "${tmpdir}/version-files"
  while IFS= read -r vfile; do
    reldir="${vfile#"${MOODLE_HTML_DIR}"/}"
    reldir="$(dirname "$reldir")"
    case "$reldir" in .|public) continue ;; esac
    if is_ignored_plugin_dir "$reldir"; then
      continue
    fi
    if [ -d "${MOODLE_SRC_DIR}/$(translate_layout_path "$reldir")" ]; then
      continue
    fi
    covered=no
    for p in $(cat "${tmpdir}/auto-paths") ${EXTRA_PLUGIN_PATHS:-}; do
      case "$reldir" in
        "$p"|"$p"/*) covered=yes; break ;;
      esac
    done
    if [ "$covered" = "yes" ]; then
      continue
    fi
    mkdir -p "${tmpdir}/auto/$(dirname "$reldir")"
    cp -a "${MOODLE_HTML_DIR}/${reldir}" "${tmpdir}/auto/${reldir}"
    printf '%s\n' "$reldir" >> "${tmpdir}/auto-paths"
    echo "  preserved third-party plugin ${reldir}"
  done < "${tmpdir}/version-files"
fi

# 3) Sync core from the immutable image tree.
#    --delete removes leftover core files from older releases (required for clean upgrades).
#    Exclude the stamp and config.php; both are restored/written after. The
#    excludes are anchored to the tree root — an unanchored "config.php" would
#    also match every theme/plugin config.php, freezing them at the old
#    version and leaving half-deleted third-party plugin skeletons behind.
mkdir -p "$MOODLE_HTML_DIR"
# --checksum: do not skip same-size/same-mtime files (matters when a volume
# was hand-edited or when tests seed trees in the same second).
rsync -a --delete --checksum \
  --exclude /config.php \
  --exclude "/${STAMP_NAME}" \
  "${MOODLE_SRC_DIR}/" "${MOODLE_HTML_DIR}/"

# 4) Restore config.php
if [ -f "${tmpdir}/config.php" ]; then
  cp -a "${tmpdir}/config.php" "${MOODLE_HTML_DIR}/config.php"
fi

# 5) Restore extra plugin paths (overwrite whatever the image shipped there),
#    relocating them when the image switched layouts (public/ in 5.1+).
if [ -d "${tmpdir}/extra" ]; then
  # shellcheck disable=SC2086
  for relpath in ${EXTRA_PLUGIN_PATHS:-}; do
    if [ -e "${tmpdir}/extra/${relpath}" ]; then
      target="$(translate_layout_path "$relpath")"
      mkdir -p "${MOODLE_HTML_DIR}/$(dirname "$target")"
      rm -rf "${MOODLE_HTML_DIR:?}/${target:?}"
      cp -a "${tmpdir}/extra/${relpath}" "${MOODLE_HTML_DIR}/${target}"
      if [ "$target" = "$relpath" ]; then
        echo "  restored ${relpath}"
      else
        echo "  restored ${relpath} → ${target} (image uses the public/ layout)"
      fi
    fi
  done
fi

# 5b) Restore auto-preserved third-party plugins, with the same relocation.
if [ -s "${tmpdir}/auto-paths" ]; then
  while IFS= read -r relpath; do
    [ -n "$relpath" ] || continue
    target="$(translate_layout_path "$relpath")"
    mkdir -p "${MOODLE_HTML_DIR}/$(dirname "$target")"
    rm -rf "${MOODLE_HTML_DIR:?}/${target:?}"
    cp -a "${tmpdir}/auto/${relpath}" "${MOODLE_HTML_DIR}/${target}"
    if [ "$target" = "$relpath" ]; then
      echo "  restored third-party plugin ${relpath}"
    else
      echo "  restored third-party plugin ${relpath} → ${target} (image uses the public/ layout)"
    fi
  done < "${tmpdir}/auto-paths"
fi

# 6) Stamp only after a successful sync
printf '%s\n' "$image_ver" > "$STAMP_FILE"

echo "Moodle code sync: done (stamp=${image_ver})."
