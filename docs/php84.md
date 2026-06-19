# PHP 8.4 (opt-in)

The default `erseco/alpine-moodle` tags ship **PHP 8.3**. PHP 8.4 is available as an
**opt-in image line**, published with a `-php84` tag suffix, for **Moodle 5.x and later**.

!!! info "Why PHP 8.3 is still the default"
    Moodle **4.5 LTS** does not support PHP 8.4, and the unsuffixed tags (`latest`,
    `main`, `vX.Y.Z`) must keep working for existing 4.x deployments. So the default
    stays on PHP 8.3 for now, and PHP 8.4 is offered separately as `-php84` tags.

## Which tag do I pull?

| Moodle version | Default tag (PHP 8.3) | Opt-in tag (PHP 8.4) |
|----------------|-----------------------|----------------------|
| Moodle 4.5.x   | `v4.5.x`              | *(not available)*    |
| Moodle 5.0.x   | `v5.0.x`              | `v5.0.x-php84`       |
| Moodle 5.1.x   | `v5.1.x`              | `v5.1.x-php84`       |
| Moodle 5.2.x   | `v5.2.x`              | `v5.2.x-php84`       |
| Moodle 5.3 LTS and later | `v5.3.x` | `v5.3.x-php84` and later |

```bash
# PHP 8.4 image for Moodle 5.2.1
docker pull erseco/alpine-moodle:v5.2.1-php84
docker pull ghcr.io/erseco/alpine-moodle:v5.2.1-php84
```

In a `docker-compose.yml`, just pin the tag:

```yaml
services:
  moodle:
    image: erseco/alpine-moodle:v5.2.1-php84
    # ...everything else is identical to the PHP 8.3 image
```

!!! warning "Moodle 4.x is not published on PHP 8.4"
    There are no `-php84` images for the 4.x line. If you run Moodle 4.5 LTS, stay on
    the default PHP 8.3 tags.

## What's different in the PHP 8.4 image?

Nothing except the PHP runtime. Same Nginx, same [Moosh](https://github.com/tmuras/moosh),
same environment variables, same multi-arch targets, same database support
(PostgreSQL, MariaDB/MySQL, SQLite). Only the PHP version changes from 8.3 to 8.4.

## How these tags are built

- The `-php84` images are built from the [`php84` branch](https://github.com/erseco/alpine-moodle/tree/php84)
  by a dedicated `build-php84.yml` workflow.
- They **never overwrite** the existing `latest`, `main`, or `vX.Y.Z` tags.
- New Moodle 5.x releases automatically get a matching `-php84` tag; the default
  PHP 8.3 tags are unaffected.

## When will PHP 8.4 become the default?

The default official tags — including `latest` — will move to PHP 8.4 once
**Moodle 5.3 LTS** (planned for **5 October 2026**) is released and becomes the new
LTS baseline. Until then, PHP 8.4 remains opt-in via the `-php84` tags.
