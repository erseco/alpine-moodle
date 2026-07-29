#!/usr/bin/env sh
#
# apply-sqlite-support.sh <MOODLE_VERSION>
#
# Build-time helper that enables experimental SQLite support (MDL-88218) for a
# checked-out Moodle tree in /var/www/html.
#
# SQLite support comes from out-of-tree patches in ateeducacion/moodle, each
# targeting its own stable branch so the diff stays applicable as branches move:
#   main    -> PR #1 (targets main;              adds the driver)
#   v5.2.x  -> PR #5 (targets MOODLE_502_STABLE; adds the driver)
#   v5.1.x  -> PR #2 (targets MOODLE_501_STABLE; adds the driver)
#   v5.0.x  -> PR #3 (targets MOODLE_500_STABLE; adds the driver)
#   v4.5.x  -> PR #4 (targets MOODLE_405_STABLE; repairs the legacy driver that
#                     4.5 still ships but that no longer installs)
# Versions without a patch keep SQLite unavailable (this is not an error).
#
# Two things need handling beyond a plain `patch`:
#
#   1. Releases whose files differ slightly from the patch's target branch may
#      reject a cosmetic hunk (e.g. a web-installer lang string). This image
#      installs SQLite via a hand-written config.php + admin/cli/install_database.php,
#      NOT the web installer, so such rejects are tolerated; the build fails only
#      if the functional SQLite PDO driver is missing afterwards.
#
#   2. The patches declare the sqlite <VENDOR> only in the newest <MOODLE
#      version> block of admin/environment.xml. When building an older release
#      whose environment.xml also carries newer version stubs, the block for the
#      version actually being installed is left without sqlite, so
#      install_database.php fails the environment check with "Error reading
#      environment data". We therefore ensure the block for the version being
#      installed declares the sqlite VENDOR (dedup-safe).
set -eu

MOODLE_VERSION="${1:?usage: apply-sqlite-support.sh <MOODLE_VERSION>}"
DIR="${MOODLE_DIR:-/var/www/html}"

case "$MOODLE_VERSION" in
  main)  pr=1 ;;
  v5.2*) pr=5 ;;
  v5.1*) pr=2 ;;
  v5.0*) pr=3 ;;
  v4.5*) pr=4 ;;
  *)
    echo "WARNING: No SQLite patch for MOODLE_VERSION=$MOODLE_VERSION (sqlite3 mode will not work)"
    exit 0
    ;;
esac

url="https://github.com/ateeducacion/moodle/pull/${pr}.diff"
echo "Applying SQLite patch from: $url"
curl -fsSL "$url" -o /tmp/sqlite.diff

# Apply what applies; tolerate rejected cosmetic hunks (see header note 1).
patch -d "$DIR" -p1 --forward --fuzz=3 < /tmp/sqlite.diff || true
find "$DIR" \( -name '*.rej' -o -name '*.orig' \) -delete
rm -f /tmp/sqlite.diff

# The SQLite PDO driver is the essential part; fail loudly if it is missing.
if [ ! -f "$DIR/lib/dml/sqlite3_pdo_moodle_database.php" ] && \
   [ ! -f "$DIR/public/lib/dml/sqlite3_pdo_moodle_database.php" ]; then
  echo "ERROR: SQLite driver missing after patching MOODLE_VERSION=$MOODLE_VERSION" >&2
  exit 1
fi

# Ensure the <DATABASE> block for the version being installed declares the
# sqlite VENDOR (see header note 2). We target that specific block because a
# release's environment.xml also carries newer version stubs, so the highest
# block is NOT the installed version (e.g. 4.5.12 declares blocks up to 5.2).
#
# For "main" the block is resolved from the tree's $branch (e.g. '503' →
# "5.3"): the patch only declares sqlite in the block that was newest when
# its diff was written, so after a weekly dev-branch bump (5.2 → 5.3dev on
# 2026-07-28) the tree's newest block predates the patch and the CLI
# installer fails with "Error reading environment data".
case "$MOODLE_VERSION" in
  v*) target="$(echo "$MOODLE_VERSION" | sed -E 's/^v([0-9]+\.[0-9]+).*/\1/')" ;;
  *)
    target=""
    for vphp in "$DIR/version.php" "$DIR/public/version.php"; do
      [ -f "$vphp" ] || continue
      branch="$(awk -F"'" '/^\$branch/ {print $2; exit}' "$vphp")"
      case "$branch" in
        [0-9][0-9][0-9])
          major="${branch%??}"
          minor="${branch#"$major"}"
          minor="${minor#0}"
          target="${major}.${minor}"
          ;;
      esac
      break
    done
    ;;
esac

if [ -n "$target" ]; then
  for envxml in "$DIR/admin/environment.xml" "$DIR/public/admin/environment.xml"; do
    [ -f "$envxml" ] || continue
    awk -v target="$target" '
      /<MOODLE version="/ {
        v = $0; sub(/.*<MOODLE version="/, "", v); sub(/".*/, "", v)
        cur = (v == target)
      }
      cur && /<DATABASE/ { inblk = 1; buf = $0; has = 0; next }
      inblk {
        buf = buf ORS $0
        if ($0 ~ /VENDOR name="sqlite"/) has = 1
        if ($0 ~ /<\/DATABASE>/) {
          if (!has) sub(/[ \t]*<\/DATABASE>/, "      <VENDOR name=\"sqlite\" version=\"3.0\" />\n    </DATABASE>", buf)
          print buf; inblk = 0; cur = 0
        }
        next
      }
      { print }
    ' "$envxml" > "$envxml.tmp" && mv "$envxml.tmp" "$envxml"
    echo "Ensured sqlite VENDOR in the <MOODLE version=\"$target\"> block of $envxml"
  done
fi

echo "SQLite support applied for $MOODLE_VERSION."
