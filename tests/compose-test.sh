#!/usr/bin/env bash
#
# tests/compose-test.sh <compose-file>
#
# Orchestrates one Moodle image test run for a given docker-compose test file:
#
#   1. Builds + starts the stack (app, its DB/redis deps and the `sut` probe).
#   2. Black-box HTTP web check: waits for the `sut` container (which runs
#      run_tests.sh) and takes its exit code as the readiness/HTTP/SQLite result.
#   3. Moodle-context moosh smoke test: runs `run_tests.sh moosh` INSIDE the
#      running `app` container (moosh needs the Moodle codebase + DB).
#
# The stack is always torn down; on any failure the container logs, the failing
# moosh output and the Moodle version are dumped for debugging.
#
# The Moodle version comes from $MOODLE_VERSION (default: main) and is injected
# into the Docker build via the compose files' ${MOODLE_VERSION:-main} build arg.
set -euo pipefail

FILE="${1:?usage: tests/compose-test.sh <compose-file>}"
export MOODLE_VERSION="${MOODLE_VERSION:-main}"

dc() { docker compose --file "$FILE" "$@"; }

dump_logs() {
  echo "::group::Diagnostics for ${FILE} (MOODLE_VERSION=${MOODLE_VERSION})"
  echo "----- docker compose ps -----"
  dc ps || true
  echo "----- app logs -----"
  dc logs --no-color app || true
  echo "----- sut logs -----"
  dc logs --no-color sut || true
  echo "::endgroup::"
}

teardown() {
  dc down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap teardown EXIT

echo "=============================================================="
echo " Moodle test: version=${MOODLE_VERSION}  compose=${FILE}"
echo "=============================================================="

# Build + start the whole stack detached so the app container stays up for the
# moosh check after the sut probe has finished.
if ! dc up --detach --build; then
  echo "ERROR: 'docker compose up' failed for ${FILE} (MOODLE_VERSION=${MOODLE_VERSION})."
  dump_logs
  exit 1
fi

# 1) Black-box HTTP web check: wait for the sut container to exit and use its
#    exit code as the result of run_tests.sh (readiness + HTTP + SQLite file).
sut_cid="$(dc ps --all --quiet sut)"
if [ -z "${sut_cid}" ]; then
  echo "ERROR: could not resolve the sut container id."
  dump_logs
  exit 1
fi

echo ">> Waiting for the HTTP web check (sut) to finish..."
sut_rc="$(docker wait "${sut_cid}")"
dc logs --no-color sut || true
if [ "${sut_rc}" != "0" ]; then
  echo "ERROR: HTTP web check failed (sut exit ${sut_rc}) for Moodle ${MOODLE_VERSION}."
  dump_logs
  exit 1
fi
echo ">> HTTP web check passed for Moodle ${MOODLE_VERSION}."

# 2) Moodle-context moosh smoke test, executed inside the running app container.
echo ">> Running the Moodle-context moosh smoke test inside app..."
if ! dc exec -T -e MOODLE_VERSION="${MOODLE_VERSION}" app sh /tmp/run_tests.sh moosh; then
  echo "ERROR: moosh smoke test failed for Moodle ${MOODLE_VERSION} (${FILE})."
  dump_logs
  exit 1
fi

echo ">> All checks passed for Moodle ${MOODLE_VERSION} (${FILE})."
