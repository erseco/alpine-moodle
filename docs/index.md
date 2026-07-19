# Alpine Moodle

A lightweight **Moodle** Docker image built on [Alpine Linux](https://alpinelinux.org/).

[![Docker Pulls](https://img.shields.io/docker/pulls/erseco/alpine-moodle.svg)](https://hub.docker.com/r/erseco/alpine-moodle/)
![Docker Image Size](https://img.shields.io/docker/image-size/erseco/alpine-moodle)
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)

## What is this image?

`erseco/alpine-moodle` packages Moodle into a single, small (~100 MB) container based on
[`erseco/alpine-php-webserver`](https://github.com/erseco/alpine-php-webserver). It runs
Nginx + PHP-FPM under a non-privileged user, includes [Moosh CLI](https://github.com/tmuras/moosh),
and is configured entirely through environment variables.

Highlights:

- **PHP 8.4** FPM with `ondemand` process manager — this docs tree is built from the `php84` image line (`-php84` tags; Moodle **5.x+ only**)
- Works with PostgreSQL, MariaDB/MySQL, or SQLite (single-container dev mode)
- Optional Redis session handler for HA deployments
- Supports Moodle **5.0**, **5.1** (with `/public` directory), **5.2+** and `main`
- **Version-aware code sync** (`SYNC_MOODLE_CODE=auto`) — upgrade Moodle core by changing the image tag even with a persistent `moodlehtml` volume ([Upgrading](upgrading.md), [#103](https://github.com/erseco/alpine-moodle/issues/103))
- Multi-arch images: `amd64`, `arm64`, `arm/v7`, `arm/v6`, `386`, `ppc64le`, `s390x`
- Internal cron via `runit` (configurable)
- Logs go straight to `docker logs`
- Extensible via pre/post configuration hooks and `POST_CONFIGURE_COMMANDS`

## Where to start

<div class="grid cards" markdown>

- :material-rocket-launch: **[Quick Start](quick-start.md)** — get a Moodle instance running in under a minute.
- :material-docker: **[Docker Compose](docker-compose.md)** — practical stacks for dev, production and proxied setups.
- :material-shield-lock: **[Reverse Proxy](reverse-proxy.md)** — Traefik, Nginx, NPM, Apache, Caddy recipes.
- :material-database: **[Environment Variables](environment-variables.md)** — every supported knob, with defaults.
- :material-harddisk: **[Persistence & Volumes](persistence.md)** — what to mount and what to back up.
- :material-language-php: **[PHP 8.4 (opt-in)](php84.md)** — `-php84` tags for Moodle 5.x while the default stays on PHP 8.3.
- :material-update: **[Upgrading](upgrading.md)** — how to move between Moodle versions safely.
- :material-lightbulb-on: **[Troubleshooting](troubleshooting.md)** — solutions to the most common deployment issues.
- :material-help-circle: **[FAQ](faq.md)** — short answers to recurring questions.

</div>

## Minimal example

```bash
docker run -d \
  -p 80:8080 \
  -e MOODLE_DATABASE_TYPE=sqlite3 \
  -e MOODLE_PASSWORD=ChangeMe123! \
  -v moodledata:/var/www/moodledata \
  erseco/alpine-moodle
```

Open <http://localhost> and log in with `moodleuser` / `ChangeMe123!`.

!!! warning "SQLite is for development and demos only"
    Use PostgreSQL or MariaDB for any real deployment. See [Docker Compose](docker-compose.md) for production-grade examples.

## Project links

- Source code: <https://github.com/erseco/alpine-moodle>
- Docker Hub: <https://hub.docker.com/r/erseco/alpine-moodle>
- GitHub Container Registry: `ghcr.io/erseco/alpine-moodle`
- Issue tracker: <https://github.com/erseco/alpine-moodle/issues>
