# Spec: SQLite works on Moodle 4.5 and 5.0+ (and is covered in CI)

Status: accepted
Background: PR #136 (introduced SQLite mode), PR #150 (version matrix CI),
`ateeducacion/moodle` PRs #1/#2/#3 (SQLite driver) and #4 (4.5) / #5 (5.2), added
by this work.

## Problem statement

The experimental SQLite mode only produced a working install on Moodle **5.2 and
main**. The version-matrix CI (PR #150) surfaced that:

- **5.0 and 5.1 fail** at `install_database.php` with *"Error reading environment
  data"* (PostgreSQL on the same versions passes).
- **4.5** has no working SQLite at all.

Two independent root causes:

1. **`environment.xml` VENDOR lands in the wrong block.** The SQLite patches
   declare the `sqlite` `<VENDOR>` only in the *newest* `<MOODLE version>` block.
   A tagged release's `environment.xml` also carries newer version stubs (e.g.
   4.5.12 lists blocks up to 5.2), so the block for the version *being installed*
   is left without SQLite and the environment check fails. This is why only
   5.2/main (whose installed version == newest block) worked.

2. **Moodle 4.5 ships a stale legacy SQLite driver.** 4.5 still bundles
   `lib/dml/sqlite3_pdo_moodle_database.php` + `lib/ddl/sqlite_sql_generator.php`
   (removed on 5.0+, which is why those branches re-add a modernised driver).
   The legacy driver was left behind as the DML/DDL base classes evolved and can
   no longer install a site: abstract `getCreateTempTableSQL`, a constructor that
   drops `$temptables`, no `temptables` init in `connect()`, and `: array`
   methods returning `false` (TypeErrors on PHP 8).

## Constraints

- alpine-moodle builds from **official** `moodle/moodle` tarballs and layers the
  `ateeducacion/moodle` SQLite patches via their PR `.diff` — the driver code
  belongs upstream, not as source edits baked into this image.
- SQLite is experimental (dev / demo / testing / WASM), not for production.

## Solution

- **`ateeducacion/moodle` PR #4** (`MOODLE_405_STABLE`) repairs the legacy 4.5
  driver (6 focused fixes; see the PR). alpine-moodle references it for `v4.5*`,
  exactly like PR #1/#2/#3 for the newer branches.
- **alpine-moodle `scripts/apply-sqlite-support.sh`** selects the right PR per
  branch, applies it (tolerating cosmetic hunk rejects), verifies the driver is
  present, and **normalises `environment.xml`** so the block for the version
  being installed declares the `sqlite` VENDOR (fixes root cause #1 uniformly for
  4.5/5.0/5.1; dedup-safe, no-op for 5.2/main).

## Acceptance criteria

- [x] SQLite installs and serves on **4.5, 5.0, 5.1, 5.2, main**.
- [x] Each version additionally passes the Moodle-context `moosh` smoke test.
- [x] The 4.5 driver fixes live upstream in `ateeducacion/moodle` PR #4; the
      image only references it + normalises `environment.xml`.
- [x] CI runs SQLite across the whole version matrix.

## Test strategy

`tests/compose-test.sh docker-compose.test.sqlite.yml` per version (HTTP web
check + SQLite DB-file check + in-container `moosh role-list`). The
`moodle-matrix` workflow's `sqlite` job covers `v4.5.12, v5.0.8, v5.1.5, v5.2.1,
main`, exercising SQLite patches PR #4 / #3 / #2 / #5 / #1 respectively (each
targeting its own stable branch; `main` alone uses PR #1).

## Validation performed (local, Docker 29.5.3 / Compose v5.1.4)

- ✅ 4.5.12 SQLite via PR #4 `.diff` on the official tarball: install completes
  (496 tables), site serves, `moosh role-list` works.
- ✅ 5.0.8 and 5.1.5 SQLite: pass after the `environment.xml` normalisation.
- ✅ 5.2.1 and main SQLite: still pass (unchanged path).
- ✅ Root-causing captured each failure (env-check, abstract generator, null
  temptables, `fetch_columns`/`get_records_sql` return types) before fixing.

## Known follow-ups (out of scope)

- The legacy 4.5 driver emits `reset()`-on-object deprecation notices at runtime
  (log noise only; queries succeed). Could be cleaned up in a later PR.
