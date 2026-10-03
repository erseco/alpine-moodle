# Image release policy

`latest` follows the newest upstream **5.3 stable** tag. Beta/RC, development builds and older releases never
publish `latest`. Automatic metadata-action `latest` generation is disabled.
Manual builds honor `moodle_version` even when dispatched against a branch.

The release workflow resolves upstream before building and publishes only after
the existing database smoke tests and image-version check pass. Do not dispatch
an old workflow revision to promote an image: it predates these protections.

Verification (2026-09-16): all shell unit suites pass, including 10 release-policy
cases (stable, older patch, older series, beta, RC, future stable, main, invalid
inputs). `actionlint .github/workflows/build.yml`, ShellCheck on the new scripts,
and `git diff --check` pass. No image publication was performed for this change.
