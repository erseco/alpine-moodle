#!/bin/sh
#
# Run the Moodle blueprint runner checks:
#   1. PHP lint of every runner file.
#   2. POSIX shell syntax check of the entrypoint hook.
#   3. The dependency-free PHP unit tests.
#
# Usage: tests/blueprint/run.sh   (override the interpreter with PHP=php8.3)
#
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
PHP="${PHP:-php}"
LIB="$ROOT/rootfs/usr/local/lib/moodle-blueprint"
fail=0

echo "== PHP lint =="
for f in $(find "$LIB" -name '*.php' | sort); do
    if "$PHP" -l "$f" >/dev/null 2>&1; then
        echo "  ok   - ${f#"$ROOT/"}"
    else
        echo "  FAIL - ${f#"$ROOT/"}"
        "$PHP" -l "$f" || true
        fail=1
    fi
done
if "$PHP" -l "$ROOT/rootfs/usr/local/bin/moodle-blueprint" >/dev/null 2>&1; then
    echo "  ok   - rootfs/usr/local/bin/moodle-blueprint"
else
    echo "  FAIL - rootfs/usr/local/bin/moodle-blueprint"
    fail=1
fi

echo "== Shell syntax =="
if sh -n "$ROOT/rootfs/docker-entrypoint-init.d/03-apply-blueprint.sh"; then
    echo "  ok   - 03-apply-blueprint.sh"
else
    echo "  FAIL - 03-apply-blueprint.sh"
    fail=1
fi

echo "== Unit tests =="
for t in "$DIR"/*Test.php; do
    echo "- $(basename "$t")"
    if ! "$PHP" "$t"; then
        fail=1
    fi
done

echo "============================"
if [ "$fail" -eq 0 ]; then
    echo "ALL BLUEPRINT CHECKS PASSED"
    exit 0
fi
echo "BLUEPRINT CHECKS FAILED"
exit 1
