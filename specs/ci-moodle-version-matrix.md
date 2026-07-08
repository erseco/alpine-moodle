# Spec: CI coverage across the supported Moodle version matrix

Status: accepted
Tracking issue: #72
Background: PR #149 (moosh broken on the Moodle 5.1+ `public/` layout)

## Problem statement

CI only builds and tests a single Moodle version (`main`) against PostgreSQL,
MariaDB and SQLite, and the only functional assertion is that the site returns
an HTTP homepage. This has two gaps:

1. **No cross-version coverage.** A change can pass CI on `main` while silently
   breaking a currently supported release. Moodle 4.5 is the current
   LTS/security-supported branch and 5.3 (represented today by `main`) is the
   next LTS, so both the legacy and the new layout must be exercised on every
   build.

2. **HTTP-only assertions miss CLI/bootstrap regressions.** Moodle 5.1 moved the
   web-accessible code root (including `version.php`) into a `public/`
   subdirectory. That layout change already broke `moosh`: the wrapper pointed
   at `/var/www/html`, where 5.1 has no `version.php`, so `moosh` could not
   bootstrap Moodle and fell back to listing only its global/no-bootstrap
   commands. When such a command runs in `POST_CONFIGURE_COMMANDS` the container
   crash-loops (fixed in PR #149). A homepage check alone does not deterministic­ally
   prove that a Moodle-context CLI command still works.

## Goals

- Every CI run validates the image against multiple Moodle versions covering
  **both** the pre-5.1 (legacy) and the 5.1+ (`public/`) layouts.
- CI verifies, per version, that:
  - Moodle is reachable over HTTP (site installed and serving), and
  - a real **Moodle-context** `moosh` command executes successfully (i.e.
    `moosh` bootstraps Moodle, not just its global command list).
- Failures clearly identify which Moodle version and database backend failed.
- The fix from PR #149 cannot silently regress.

## Non-goals

- Full browser/Behat/PHPUnit end-to-end testing of Moodle itself.
- Testing every patch release or every DB × version combination (see Constraints).
- Changing the production runtime image behavior.

## Constraints

- The Dockerfile downloads Moodle from `refs/tags/${MOODLE_VERSION}` (or `main`),
  so version values must be **real git tags**; there is no bare `v4.5` tag.
  Patch tags are pinned to the latest available at implementation time and
  refreshed as needed. This is documented, not hidden.
- SQLite mode depends on out-of-tree patches that only exist for Moodle **5.0+**
  (see Dockerfile), so SQLite cannot cover 4.5.
- `moosh` lives only inside the `app` container (it needs the Moodle codebase and
  DB access), so the Moodle-context `moosh` check must run **inside `app`**, not
  in the black-box `sut` probe container.
- Cost control: a full 5-versions × 3-databases matrix is wasteful. PostgreSQL
  (the default backend) covers all versions; MariaDB and SQLite cover a smaller
  representative subset that still spans both layouts.
- Keep workflow logic DRY: the up/wait/assert/teardown logic lives in one shared
  script used by both the release build and the version matrix.

## Version matrix (pinned at implementation time)

| Moodle    | Layout        | PostgreSQL | MariaDB | SQLite |
|-----------|---------------|:----------:|:-------:|:------:|
| v4.5.12   | legacy        | ✅         | ✅      | —¹     |
| v5.0.8    | legacy        | ✅         | —       | ✅     |
| v5.1.5    | public/       | ✅         | —       | —      |
| v5.2.1    | public/       | ✅         | ✅      | —      |
| main (5.3-dev) | public/  | ✅         | —       | ✅     |

¹ SQLite patches exist only for Moodle 5.0+; 4.5 has no SQLite support.

- PostgreSQL: all five versions (legacy + public/ coverage).
- MariaDB: v4.5.12 (legacy) + v5.2.1 (public/) — one of each layout.
- SQLite: v5.0.8 (legacy, has patch) + main (public/) — one of each layout.

Latest tags at implementation time: v4.5.12, v5.0.8, v5.1.5, v5.2.1.

## Acceptance criteria

- [ ] CI runs a matrix that builds & tests Moodle 4.5, 5.0, 5.1, 5.2 and main.
- [ ] The matrix passes the selected `MOODLE_VERSION` into the Docker build.
- [ ] Each job asserts Moodle is reachable over HTTP.
- [ ] Each job asserts a Moodle-context `moosh` command succeeds and does **not**
      fall back to the global/no-bootstrap command list.
- [ ] The moosh assertion covers both the legacy and the `public/` layout, so a
      PR #149-style regression fails CI.
- [ ] Job names identify the Moodle version and database backend.
- [ ] On failure the logs include container logs, the failing `moosh` output and
      the Moodle version used.

## Test strategy

- **HTTP readiness / web check** — unchanged responsibility of `run_tests.sh`
  running in the black-box `sut` container: wait for the port, then assert an
  HTTP 200 homepage carrying stable Moodle markers.
- **Moodle-context `moosh` smoke test** — a new `moosh` mode in `run_tests.sh`,
  executed **inside the `app` container**. It runs `moosh role-list` (a command
  that requires a bootstrapped Moodle + DB), and fails if:
  - `moosh` exits non-zero, or
  - the output shows the global/no-bootstrap fallback
    (`No command provided … possible commands in current context`), or
  - the output lacks the standard Moodle roles.
  `role-list` is chosen because it is the exact command PR #149 used to
  reproduce the regression, is read-only/deterministic, and works across
  4.5 → main.
- **Orchestration** — `tests/compose-test.sh <compose-file>` brings the stack up,
  waits for the `sut` HTTP check, runs the `moosh` mode inside `app`, dumps
  container logs on failure and tears the stack down. Reused by `build.yml`
  (release build) and `moodle-matrix-tests.yml` (version matrix).

## Validation performed

Documented in the PR: at least one legacy-layout version and one `public/`-layout
version are built and tested locally; anything not runnable locally is called out.
