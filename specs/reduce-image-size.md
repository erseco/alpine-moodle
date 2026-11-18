# Reduce the image footprint without breaking upgrades (research)

Status: proposal / experiment, not a runtime change. This is independent of the
Ghostscript feature (#196). Do not merge a storage-layout change without the
measurements and migration checks below.

## Current baseline

The Dockerfile downloads the pinned upstream Moodle commit into
`/usr/src/moodle`, applies the optional SQLite patch, then copies the entire
tree to `/var/www/html` and writes the release stamp. Both copies are included
in the image layers. The source is used by
`rootfs/docker-entrypoint-init.d/010-sync-moodle-code.sh` to refresh persisted
code before the normal configuration/database upgrade. This addresses #103,
#161 and related plugin-preservation regressions. Removing the seed without
checking these contracts is not safe.

Published v5.2.4 amd64 reference: approximately 205.44 MB compressed, with two
large Moodle layers of approximately 84.35 and 84.39 MB. This is a historical
registry observation, not a controlled benchmark of current main. Eliminating
one full tree could save up to ~84 MB (~41% of that baseline). A first-boot
copy consumes disk in the writable layer or named volume, so image download
savings are not necessarily host storage savings. With Ghostscript (+~20–26
MB estimated), the illustrative net size could be ~141–147 MB compressed;
the actual build is the authority.

## Comparison with existing images and Docker documentation

- [Official WordPress entrypoint](https://github.com/docker-library/wordpress/blob/master/docker-entrypoint.sh):
  a source tree in /usr/src/wordpress is copied into the runtime directory on
  first use, with special treatment of existing plugin content and ownership.
  Good precedent for runtime seeding, but it does not implement our
  version-aware upgrade contract.
- [Moodle HQ moodle-docker](https://github.com/moodlehq/moodle-docker):
  developer/test infrastructure mounts a separately checked-out Moodle tree
  (MOODLE_DOCKER_WWWROOT). This avoids embedding Moodle in the PHP image, but
  shifts checkout/version selection to operators and is not equivalent to a
  self-contained production release.
- [Bitnami Moodle](https://github.com/bitnami/containers/tree/main/bitnami/moodle):
  documents first-run initialization and separate persistent Moodle code and
  data directories. Useful precedent for separation, not proof that it has
  the same upgrade guarantees or a comparable image size. The current
  commercial image and older legacy images should not be conflated.
- Context7, Docker official docs (/docker/docs): [volumes](https://docs.docker.com/engine/storage/volumes/)
  and [bind mounts](https://docs.docker.com/engine/storage/bind-mounts/) explain
  automatic population of empty named volumes and masking image files;
  [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
  explains COPY --chown and COPY --link (layer reuse, not hard-linking
  duplicate file contents); [multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
  keep build-only content outside the final image.
- [Moodle upgrade procedure](https://docs.moodle.org/en/Upgrading):
  replace core code, preserve configuration and compatible custom plugins,
  then upgrade the DB. Only supported upstream upgrade paths are in scope.

## Options

| Option | Registry savings vs reference | Runtime/compatibility implications |
| --- | --- | --- |
| Keep both trees | 0 | Current behavior; safest baseline |
| One source tree, seed at startup | Up to ~84 MB | Extra first-boot I/O and writable-layer storage; empty/never mode and downstream Dockerfile contracts need explicit solutions |
| Build-stage source then copy final patched tree once | Small unless duplication also removed | Useful for intermediate patch/cache files, not sufficient alone |
| Hardlink two trees in a single layer | Potentially comparable to one tree; benchmark | Shared inode/overlay copy-up semantics can contaminate the source or behave differently across storage drivers; not recommended without isolation proof |
| Compressed archive as recovery source plus expanded runtime | Likely limited compressed transfer savings | Preserves pre-populated runtime, but duplicate compressed content and archive unpack cost |
| Symlink runtime to source | Potentially comparable to one tree | A volume masks the symlink, and plugin edits may alter the recovery source; reject as a default |
| Runtime download or externally supplied source | Up to both Moodle layers | Requires network/host source on startup, weakens release reproducibility/offline use; reject as a default |

Prefer the single packaged source + explicit first-run copy model if the
compatibility contract can be met. Do not remove the build-time seed as a
standalone change. Consider keeping the existing layout as a compatibility
target only if evidence shows it is needed; avoid multiple release variants
unless their maintenance cost is justified. Do not aggressively delete upstream
tests, vendor dependencies, localization data, license files or PHP extensions
without auditing Moodle/Moosh/blueprint requirements.

## Reproducible size experiment

Use the exact same upstream commit, base image digest, PHP version,
architecture and Ghostscript presence for both builds. Build v4.5.14
(PHP 8.3), v5.2.4 (PHP 8.3 and optional 8.4) and v5.3.0 (PHP 8.4); start with
amd64/arm64, then verify ppc64le/s390x. Pin Composer and Moosh inputs as well
where possible; otherwise disclose the drift. Resolve MOODLE_COMMIT to the
peeled upstream Git tag. Use separate baseline and candidate worktrees.

For each single-platform build, export OCI archives using e.g.:

```sh
docker buildx build --platform linux/amd64 \
  --build-arg MOODLE_VERSION=v5.2.4 \
  --build-arg MOODLE_COMMIT="$MOODLE_COMMIT" \
  --build-arg PHP_VERSION=83 \
  --build-arg PHP_WEBSERVER_VERSION=3.24-php83 \
  --provenance=false --sbom=false \
  --output type=oci,dest=/tmp/baseline.oci.tar .
# Run the same command in the candidate worktree with dest=/tmp/candidate.oci.tar.
python3 scripts/compare-oci-size.py /tmp/baseline.oci.tar /tmp/candidate.oci.tar
```

The size helper compares actual layer descriptor byte lengths, not the size
of an outer tar, and reports each platform independently. Do not treat
attestation manifests as runnable images. For a local --load build also record
`docker image inspect --format '{{.Size}}' IMAGE`, `docker history --no-trunc IMAGE`,
and `docker system df -v`. Measure writable layer with `docker ps --size`, data
and code volume use with du, and elapsed time until HTTP readiness for fresh
and existing volumes. Include warm restarts, initial seed and upgrade time,
peak disk during replacement, and shared-layer reuse across tags. Compare
Trivy findings and package inventory; size alone is not a merge criterion.

## Required migration and acceptance matrix

Use disposable copies of fixture volumes and explicit previous **published**
images, not only two builds of the candidate Dockerfile. The current
tests/upgrade-test.sh builds both ends from the same checkout, which cannot
prove migration from the already-published old image layout. Extend it or add
a separate test parameter for the old published image (pin a digest).
Never delete a user's existing volume to make an upgrade pass.

- [ ] Fresh installs with no html mount, fresh default named volume, empty
  bind mount owned by UID 65534 and volume-nocopy; validate ownership and
  source seed availability before config, composer, plugins or Nginx run.
- [ ] Existing populated html/data volumes from released 4.5.x/5.0.x
  (legacy version.php) and 5.1+/5.2.x (public/version.php), including same
  Moodle version rebuild, patch update and supported 4.5 → 5.3 upgrade.
  Test the public/ move via supported upstream paths, not a forced downgrade.
- [ ] Preserve root config.php contents, DB/config customizations, users,
  courses, submissions and file hashes; preserve third-party plugins,
  nested subplugins (#191), custom themes and EXTRA_PLUGIN_PATHS including
  relocation across public/. Retired core plugins must still be removed.
- [ ] SYNC_MOODLE_CODE=auto/always/never and SYNC_PRESERVE_PLUGINS=true/false.
  For never, existing code must win untouched; a fresh default named volume
  currently has image code even when sync is disabled. Reproduce that
  contract (or propose and explicitly review a migration) rather than silently
  changing never semantics. Check AUTO_UPDATE_MOODLE=false too.
- [ ] Derived images that COPY files/plugins into /var/www/html during build;
  init hooks, overrides MOODLE_SRC_DIR/MOODLE_HTML_DIR, custom entrypoints and
  CLI with --entrypoint must be assessed. A source-only image leaves paths
  missing before entrypoint, and default sync may delete derived plugins on
  first seed (html_has_code=no). Define a non-destructive migration path
  before changing the public extension contract.
- [ ] Rootless UID/GID 65534, read-only mounts and config file bind mount;
  existing permission errors must fail clearly, not run as root or silently
  delete files. Do not assume Docker volume ownership fixes bind mounts.
- [ ] Simulate an interrupted sync and retry. Do not publish the release
  stamp until code and restored plugins are complete; preserve recovery data
  if an interruption can otherwise lose plugin files. Verify no unintended
  writes into the packaged source. No automatic downgrade of database/code.
- [ ] Offline startup for installations where existing composer/plugin
  dependencies are available; no new network requirement for Moodle core.
- [ ] Run the Moodle matrix, tests/compose-test.sh, tests/upgrade-test.sh,
  tests/verify-moodle-version.sh, SQLite patch and Moosh checks, HTTP status
  checks, and restart/cron; update release-gate expectations if source-only
  layout changes pre-entrypoint version verification.
- [ ] Build all published architectures. Record actual compressed/uncompressed
  delta and startup/storage tradeoffs in this PR before proposing a production
  layout change.

Target: a meaningful download saving (ideally at least 60 MB on the measured
v5.2.4 amd64 baseline) with no loss of data or supported deployment behavior.
If the compatibility work or extra runtime storage outweighs the benefit,
keep the current layout and consider smaller build-stage optimizations first.

## Decision

This PR is deliberately research-only: no change to Dockerfile, entrypoint,
release tags or existing users. Follow-up implementation should use the
measurements and acceptance criteria above, with a separately reviewable
migration change and rollback documentation (restore DB and volumes from a
backup; reverting the image alone cannot undo a Moodle DB upgrade).
