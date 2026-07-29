#!/usr/bin/env sh
#
# tests/unit/test-verify-moodle-version.sh
#
# Fast, docker-free unit tests for tests/verify-moodle-version.sh (#161).
# Stubs the docker CLI with a script that emits a canned version.php, so the
# parsing and match/mismatch logic can be exercised without images.
#
# Run from the repository root:
#   ./tests/unit/test-verify-moodle-version.sh
#
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
SCRIPT="${ROOT}/tests/verify-moodle-version.sh"
FAILED=0

if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: verify script not found at $SCRIPT"
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Stub docker: ignores every argument and prints the canned version.php that
# the current test case wrote to $STUB_VERSION_PHP.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/docker" <<'EOF'
#!/usr/bin/env sh
cat "$STUB_VERSION_PHP"
EOF
chmod +x "$WORK/bin/docker"
PATH="$WORK/bin:$PATH"
export STUB_VERSION_PHP="$WORK/version.php"

# run_case LABEL EXPECTED_EXIT TAG
# The canned version.php must already be in $STUB_VERSION_PHP.
run_case() {
  label="$1"
  expected_exit="$2"
  tag="$3"
  set +e
  sh "$SCRIPT" fake-image:latest "$tag" > "$WORK/out.log" 2>&1
  actual_exit=$?
  set -e
  if [ "$actual_exit" = "$expected_exit" ]; then
    echo "  PASS: $label"
  else
    echo "  FAIL: $label (expected exit=$expected_exit actual=$actual_exit)"
    sed 's/^/        /' "$WORK/out.log"
    FAILED=$((FAILED + 1))
  fi
}

write_release() {
  cat > "$STUB_VERSION_PHP" <<EOF
\$version  = ${2:-2026042001.00};              // 20260420      = branching date YYYYMMDD - do not modify!
\$release  = '$1';    // Human-friendly version name
\$branch   = '502';                      // This version's branch.
EOF
}

echo "== stable tag matches release"
write_release "5.2.1 (Build: 20260608)"
run_case "v5.2.1 vs 5.2.1" 0 v5.2.1

echo "== stable tag vs stale dev snapshot (the #161 scenario)"
write_release "5.2dev (Build: 20251219)"
run_case "v5.2.1 vs 5.2dev" 1 v5.2.1

echo "== stable tag vs weekly + build must not pass"
write_release "5.2.1+ (Build: 20260612)"
run_case "v5.2.1 vs 5.2.1+" 1 v5.2.1

echo "== pre-5.1 root layout release string"
write_release "4.5.12 (Build: 20260608)" 2024100712.00
run_case "v4.5.12 vs 4.5.12" 0 v4.5.12

echo "== main only requires a parseable release"
write_release "5.3dev (Build: 20260724)"
run_case "main vs 5.3dev" 0 main

echo "== pre-release tags skip the strict match"
write_release "5.2rc2 (Build: 20260410)"
run_case "v5.2.0-rc2 vs 5.2rc2" 0 v5.2.0-rc2
write_release "5.2beta (Build: 20260320)"
run_case "v5.2.0-beta vs 5.2beta" 0 v5.2.0-beta

echo "== missing/unparseable version.php fails"
: > "$STUB_VERSION_PHP"
run_case "empty version.php" 1 v5.2.1
run_case "empty version.php (main)" 1 main

echo "== unexpected tag format fails"
write_release "5.2.1 (Build: 20260608)"
run_case "garbage expected version" 1 not-a-version

if [ "$FAILED" -gt 0 ]; then
  echo "FAILED: $FAILED case(s)"
  exit 1
fi
echo "All verify-moodle-version tests passed."
