# Stable 5.3 promotion — release gate

Keep this PR **draft** until Moodle 5.3 stable is published (target 2026-10-05).
It includes merged #170/#171/#173 and is based on current `main`.
This includes the Hadolint fix, serialized latest promotion and single-source
5.3 stable policy. Promotion tests also reject a late 5.2 build after the switch.
Do not merge merely because
the beta tests pass.

This change selects PHP 8.4/Alpine base 3.23 for local default builds, development,
and Moodle 5.3+. Release CI explicitly retains PHP 8.3/base 3.20 for 4.5 and
unsuffixed 5.0–5.2 tags. It moves `latest` eligibility from 5.2 to the newest
upstream 5.3 stable tag. No historical tags are rewritten or deleted by the PR.

Before merging:

- Verify upstream's actual stable tag and its final environment.xml requirements.
- Retarget/rebase the fork's SQLite PR onto MOODLE_503_STABLE when available.
- Update the beta pin in the CI matrix and upgrade test to the stable tag; run
  all three database smoke tests and the persistent upgrade test on that tag.
- Validate the final plugin/theme inventory in staging and a restore of the
  database + files backup. Audit the PHP/base image security patch status.
- Confirm users of 4.5 are pinned to `v4.5.x`; its security support runs to
  2027-10-04. PHP 8.3 compatibility does not resolve the old base's support gap.

Local policy tests exercise future stable 5.3 selection, exclusion of beta/RC,
older patch/series protection, and retained PHP 8.3 on 4.5/5.2. Runtime behavior
is covered by the readiness PR's PHP 8.4 beta and real upgrade tests. Stable
5.3 itself cannot be tested before it exists; no production promotion has run.

## Further betas, RCs and runtime policy

The existing daily tag sync discovers new upstream tags; `v5.3.0-beta`,
numbered `-beta1`/`-beta2` and `-rc1`/`-rc2`/`-rc10` are accepted by the release
policy. They build with PHP 8.4 under their exact tags, never `latest`.
The image verification gate requires the corresponding Moodle release string:
for example `5.3beta2` or `5.3rc2`, and rejects stale prereleases or an RC
masquerading as final. These are synthetic regression cases, not a prediction
that upstream will publish those exact tags. A moved existing upstream tag is
not detected as a new tag; rebuild it explicitly if required.

The CI matrix and persistent upgrade test intentionally remain pinned to the
first 5.3 beta. Refresh those pins when adopting a new beta/RC, then the actual
stable tag, to qualify that specific version before promotion. Tag builds also
run their own database smoke tests and exact-version publication gate.

After this PR is merged, the runtime mapping is:

| Image tag | PHP |
| --- | --- |
| `v4.5.x` | 8.3 |
| Unsuffixed `v5.0.x`, `v5.1.x`, `v5.2.x` | 8.3 (preserved compatibility) |
| Existing 5.0–5.2 `-php84` variants | 8.4 |
| `v5.3.x`, including beta/RC, and subsequent series | 8.4 |
| `main` / `beta` development aliases | 8.4 |
| `latest` | 8.4, newest stable 5.3 only |

Before this PR is merged, `latest` stays on stable 5.2/PHP 8.3 and `main`/`beta`
remain PHP 8.3; explicit 5.3 beta/RC tags already use PHP 8.4. This PR does not
silently change the runtime of historical unsuffixed 5.0–5.2 images.

Additional local regression coverage: 16 runtime cases, 15 release-policy
cases and 19 exact-version checks, including numbered beta/RC and mismatch
rejection. Future prereleases and final still need real-image tests when issued.
