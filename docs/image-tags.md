# Image tags

Every Moodle release is published as `vX.Y.Z`, the main tag, and also without the `v`.
Series tags always point at the newest release of their series, so `4.5` gets every
4.5 LTS security release without editing your compose file.

| Tag | Image | Example |
|-----|-------|---------|
| `vX.Y.Z` | that exact release | `v5.2.4` |
| `X.Y.Z` | the same image as `vX.Y.Z` | `5.2.4` |
| `X.Y` | newest release of Moodle X.Y, moves with every patch release | `4.5` |
| `X` | newest release of Moodle X, moves to new series too (5.3 → 5.4) | `5` |
| `X.Y-php84`, `X.Y.Z-php84` | opt-in [PHP 8.4](php84.md) line for Moodle 5.0–5.2 | `5.2-php84` |
| `latest` | newest Moodle 5.3 LTS release ([release policy](release-policy.md)) | |
| `main`, `beta` | Moodle development branch | |

Beta and RC releases are also published without the `v` (`5.3.0-rc2`), but never move a
series tag. Only Moodle 4.5 and newer get the tags without `v`.

```yaml
services:
  moodle:
    image: erseco/alpine-moodle:4.5 # always the newest 4.5.x
```

!!! warning "Prefer `X.Y` in production"
    An `X` tag (`5`) switches to the next Moodle series as soon as it is released, which
    upgrades the database and cannot be rolled back. Use `X.Y` to stay on a series and
    `vX.Y.Z` to pin an exact build.

## How they are published

The `image-aliases` workflow runs after every successful image build (`buildx` and
`build-php84`). It reads the release tags of the repository, computes the aliases with
`scripts/image-aliases.sh plan` and copies the exact multi-arch image of each release to
its aliases on Docker Hub and GHCR (`scripts/sync-image-aliases.sh`), so nothing is
rebuilt. Aliases already on the right image are left alone and releases whose build has
not finished yet are skipped, so a late build of an older patch never moves a series tag
back. The same workflow updates the Docker Hub description with the current tag list.

Run it by hand from the Actions tab (*image-aliases* → *Run workflow*) to republish every
alias, for example after a registry clean-up.
