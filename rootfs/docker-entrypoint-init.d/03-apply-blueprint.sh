#!/bin/sh
#
# Apply a Moodle Playground-compatible blueprint after Moodle has been
# installed/upgraded (this hook sorts after 02-configure-moodle.sh).
#
# This is an additional declarative provisioning layer; it never replaces the
# environment-variable configuration. When no blueprint variable is set the
# hook exits successfully without doing anything.
#
# Behaviour on failure is controlled by MOODLE_BLUEPRINT_ON_ERROR:
#   abort (default) -> fail container startup if blueprint application fails
#   warn            -> print a warning and continue startup
#
set -eu

# Skip quickly when no blueprint source is configured.
if [ -z "${MOODLE_BLUEPRINT:-}" ] && \
   [ -z "${MOODLE_BLUEPRINT_URL:-}" ] && \
   [ -z "${MOODLE_BLUEPRINT_BUNDLE:-}" ]; then
    echo "[blueprint] No blueprint variable set; skipping."
    exit 0
fi

on_error="${MOODLE_BLUEPRINT_ON_ERROR:-abort}"
case "$on_error" in
    abort|warn) ;;
    *)
        echo "[blueprint] ERROR: invalid MOODLE_BLUEPRINT_ON_ERROR='$on_error' (expected 'abort' or 'warn')." >&2
        exit 1
        ;;
esac

echo "[blueprint] Applying Moodle blueprint..."

# The runner reads the MOODLE_BLUEPRINT* environment variables directly.
if /usr/local/bin/moodle-blueprint apply; then
    echo "[blueprint] Blueprint applied."
    exit 0
fi

# Application failed: respect the configured error policy.
if [ "$on_error" = "warn" ]; then
    echo "[blueprint] WARNING: blueprint application failed; continuing startup (MOODLE_BLUEPRINT_ON_ERROR=warn)." >&2
    exit 0
fi

echo "[blueprint] ERROR: blueprint application failed; aborting startup (MOODLE_BLUEPRINT_ON_ERROR=abort)." >&2
exit 1
