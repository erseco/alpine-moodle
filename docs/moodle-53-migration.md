# Moodle 5.3 LTS preparation

## Rollout and dependencies

1. Merge the release-policy PR first. It keeps `latest` on the newest 5.2 stable.
2. Review [the dedicated 5.3 SQLite patch](https://github.com/ateeducacion/moodle/pull/7)
   and this readiness change. `v5.3.0-beta`/RC builds select PHP 8.4, but stable
   and development defaults remain PHP 8.3 until the separate promotion PR.
3. Promote the 5.3 stable line only after upstream releases it and validation
   passes. Keep that PR draft until then. Keep `v4.5.x` on PHP 8.3.

Upstream has no `MOODLE_503_STABLE` on 2026-09-16. The fork PR currently targets
`feature/moodle-53-baseline` at the exact beta tag. Retarget/rebase to the upstream
stable branch when available; do not repurpose the existing main or 5.2 patches.

The default build now selects a base/runtime pair from `scripts/image-runtime.sh`.
Both runtimes use the current main code and its router/config permissions fixes.
The legacy php84 branch remains responsible only for opt-in 5.0–5.2 tags.
New 5.3 prereleases use unsuffixed version tags on PHP 8.4. A single Dockerfile
also supports explicit PHP 8.4 test builds using the two arguments below.

Only 64-bit architectures are published by the updated default workflow:
amd64, arm64, ppc64le, s390x. Existing tags are not deleted.

## Reproducible checks

From this checkout, with Docker running:

```sh
for t in tests/unit/*.sh; do "$t"; done
actionlint .github/workflows/build.yml .github/workflows/moodle-matrix-tests.yml
export MOODLE_VERSION=v5.3.0-beta PHP_VERSION=84 PHP_WEBSERVER_VERSION=3.23
./tests/compose-test.sh docker-compose.test.yml
./tests/compose-test.sh docker-compose.test.mariadb.yml
./tests/compose-test.sh docker-compose.test.sqlite.yml
./tests/upgrade-test.sh
```

Use distinct `COMPOSE_PROJECT_NAME` values when running backends concurrently.
The upgrade script chooses its own isolated project and removes only its test
volumes on exit. It installs 4.5.14/PHP 8.3 on PostgreSQL 17, creates a course,
data file and local plugin, then updates the same database/code/data volumes to
5.3 beta/PHP 8.4. It checks preserved data and plugin installation, Moosh,
Moodle status, cron, and another restart. This is not a compatibility certification
for third-party plugins: test the actual site's plugins in staging too.

## Production migration

Moodle 4.5 general support ended 2025-10-06; security ends 2027-10-04.
Moodle 5.3 LTS is planned for 2026-10-05, with security through 2029-10-01.
Sources: [release calendar](https://moodledev.io/general/releases) and
[5.3 requirements](https://moodledev.io/general/releases/5.3).

Use a separate staging stack restored from a consistent database + moodledata +
config/plugins backup. Pin database image versions; the **actual 5.3 beta
environment.xml requires PostgreSQL 17 and MariaDB 11.4** (MySQL remains 8.4),
despite the release-notes page still listing older minima. Use the tagged code's
requirements as the release gate. Update an older database first while still on
4.5/PHP 8.3. Then test the direct 4.5 → 5.3 update; intermediate Moodle releases
are not required. Rollback means restoring the database AND files, not merely
switching to the older image.

Base-image maintenance is still required: Alpine 3.20 is past regular support,
and Alpine's community repository has a shorter lifecycle than main. Keeping
PHP 8.3 for 4.5 is a compatibility decision, not proof that its packages are
patched. Audit/rebuild the separate alpine-php-webserver base before production.
Do not move blindly to Alpine 3.24: the existing php84 work recorded Composer
pulling PHP 8.5 there. PHP 8.4 security support ends 2028-12-31, so plan another
runtime review during 5.3's lifetime.

## Validation results

Local checks on 2026-09-16: all shell unit suites and blueprint checks pass;
actionlint for the changed build/matrix workflows, ShellCheck for the new test
orchestration/runtime scripts, PHP lint and `git diff --check` pass.

The exact beta/PHP 8.4 installed successfully with PostgreSQL, MariaDB and
SQLite and passed HTTP, Moosh, status checks, code sync and restart. Those runs
found and verified the fix for the 3.23 Nginx fallback spelling. The real upgrade
test additionally exposed retired core plugins being misidentified as custom
plugins; preservation now consults Moodle's own deleted-plugin manifest, with
a regression check for qtype_random versus a custom question type.

The persistent upgrade result and remote CI results will be recorded after
completion. Local Docker runs use arm64; CI exercises amd64. Other published
64-bit platforms have not been execution-tested locally. No production stack
or registry tag has been changed by these tests.
