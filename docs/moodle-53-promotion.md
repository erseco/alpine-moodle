# Stable 5.3 promotion — release gate

Keep this PR **draft** until Moodle 5.3 stable is published (target 2026-10-05).
It depends on the release-policy and readiness PRs. Do not merge merely because
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
