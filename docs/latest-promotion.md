# Deterministic `latest` publication

Tag sync may build releases in any order. Builds publish their version tags,
never `latest` directly (`metadata-action` also has `latest=false`). After all
release checks pass, an eligible stable build enters a separate promotion job.

The job holds the repository-wide `moodle-latest-promotion` concurrency lock
and checks out **current `main` policy**, then queries upstream again. Only
the newest stable patch in the selected production line may promote. Currently
that line is **5.3 LTS**, selected by `stable_pattern` in `scripts/release-policy.sh`.
Merge this promotion only when the stable LTS gates are satisfied. Beta, RC, `main`,
older patches and other series cannot replace `latest`.

`docker buildx imagetools create` copies the successful build's immutable
multi-architecture digest to `latest` in Docker Hub and GHCR. It does not rebuild
or read a mutable version tag. No sleeps or build ordering are required.

The concurrency queue uses `queue: max`, not the default single pending slot:
otherwise a late old build could evict a newer pending promotion. GitHub permits
up to 100 pending jobs; beyond that, rerun canceled jobs. Writes across two
registries are not transactional: a failed registry write fails the job; rerun
it to reconcile both. If the newest upstream release has not built successfully,
the previous `latest` remains until it does.

## Rollout and recovery

- Merge this policy before the next tag synchronization. Allow already-running
  old workflows to finish first: historical workflow definitions cannot acquire
  the new lock automatically. Do not rerun historical tag workflows to publish.
- To rebuild an existing release using current policy, dispatch **buildx** on
  **main**, supplying `moodle_version` (the newest upstream 5.3 stable patch).
  Historical Git tags are not rewritten.
- Compare `docker buildx imagetools inspect erseco/alpine-moodle:latest` and
  `docker buildx imagetools inspect ghcr.io/erseco/alpine-moodle:latest` with the
  successful build's digest after rollout. This PR does not publish images.

## Verification

Passed locally: all shell unit suites (runtime, release policy, code sync,
version verification and new promotion regression tests), Bash syntax,
ShellCheck for changed scripts, and `git diff --check`.

The promotion test mocks upstream Git and Docker writes: numeric tag ordering,
both registries receiving the exact digest, late old builds, prereleases,
other stable series, a newer release appearing during a build, empty upstream
results, invalid inputs, network failure and registry failure. It makes no
production registry writes. Run:

```sh
bash tests/unit/test-promote-latest.sh
shellcheck scripts/release-policy.sh scripts/promote-latest.sh tests/unit/test-promote-latest.sh
```

Local actionlint 1.7.12 does not yet recognize `concurrency.queue`; with only
that known schema warning filtered, the workflow passes. The property is
documented by GitHub and is also validated by GitHub when the PR workflow runs.

References: [GitHub concurrency and queue limits](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
[Docker manifest-index copying](https://docs.docker.com/reference/cli/docker/buildx/imagetools/create/).
