# Alpine Moodle

[![Docker Pulls](https://img.shields.io/docker/pulls/erseco/alpine-moodle.svg)](https://hub.docker.com/r/erseco/alpine-moodle/)
![Docker Image Size](https://img.shields.io/docker/image-size/erseco/alpine-moodle)
![nginx 1.26](https://img.shields.io/badge/nginx-1.26-brightgreen.svg)
![php 8.3](https://img.shields.io/badge/php-8.3-brightgreen.svg)
![moodle](https://img.shields.io/badge/moodle-configurable-yellow)
![moosh 1.27](https://img.shields.io/badge/moosh-1.27-orange)
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Build Status](https://github.com/erseco/alpine-moodle/actions/workflows/build.yml/badge.svg)

A lightweight **Moodle** Docker image built on [Alpine Linux](https://alpinelinux.org/) — ~100 MB, PHP 8.3 FPM, Nginx, multi-arch, configured entirely through environment variables.

> 📚 **Full documentation: <https://erseco.github.io/alpine-moodle/>**

The documentation site covers quick start, `docker-compose` recipes, reverse proxy setups (Traefik, Nginx, NPM, Apache, Caddy), every supported environment variable, persistence and upgrade workflows, and a troubleshooting section built from the most frequent support questions.

## Quick start

### Single container (SQLite — dev/demo only)

```bash
docker run -d \
  -p 80:8080 \
  -e MOODLE_DATABASE_TYPE=sqlite3 \
  -e MOODLE_PASSWORD=ChangeMe123! \
  -v moodledata:/var/www/moodledata \
  erseco/alpine-moodle
```

Open <http://localhost> and log in with `moodleuser` / `ChangeMe123!`.

### With PostgreSQL (recommended)

```yaml
services:
  postgres:
    image: postgres:alpine
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: moodle
      POSTGRES_USER: moodle
      POSTGRES_DB: moodle
    volumes:
      - postgres:/var/lib/postgresql

  moodle:
    image: erseco/alpine-moodle
    restart: unless-stopped
    environment:
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: ChangeMe123!
    ports:
      - "80:8080"
    volumes:
      - moodledata:/var/www/moodledata
      - moodlehtml:/var/www/html
    depends_on:
      - postgres

volumes:
  postgres:
  moodledata:
  moodlehtml:
```

```bash
docker compose up -d
```

For production deployments (reverse proxy, TLS, Redis, tuning, upgrades), see the [documentation site](https://erseco.github.io/alpine-moodle/).

## Key features

- Compact image (~100 MB) built on [`erseco/alpine-php-webserver`](https://github.com/erseco/alpine-php-webserver)
- PHP 8.3 FPM with `ondemand` process manager — idles near-zero CPU
- PostgreSQL, MariaDB/MySQL **or** SQLite (single-container dev mode)
- Optional Redis session handler
- Supports Moodle 4.x, 5.0, 5.1+ (auto-detects `/public` layout) and `main`
- Multi-arch: `amd64`, `arm64`, `arm/v7`, `arm/v6`, `386`, `ppc64le`, `s390x`
- [Moosh CLI](https://github.com/tmuras/moosh) bundled for automation
- Pre/post configuration hooks (`PRE_CONFIGURE_COMMANDS`, `POST_CONFIGURE_COMMANDS`)
- Runs as the non-privileged `nobody` user
- Logs to `stdout` / `stderr` — just `docker logs -f`
- Internal cron via `runit` (configurable, or run it externally)

## Registries

- Docker Hub: `erseco/alpine-moodle`
- GitHub Container Registry: `ghcr.io/erseco/alpine-moodle`

## Documentation

The full, searchable documentation lives at **<https://erseco.github.io/alpine-moodle/>**:

- [Quick Start](https://erseco.github.io/alpine-moodle/quick-start/)
- [Docker Compose examples](https://erseco.github.io/alpine-moodle/docker-compose/)
- [Reverse proxy guides](https://erseco.github.io/alpine-moodle/reverse-proxy/) (Traefik, Nginx, NPM, Apache, Caddy)
- [Environment variables reference](https://erseco.github.io/alpine-moodle/environment-variables/)
- [Persistence & volumes](https://erseco.github.io/alpine-moodle/persistence/)
- [Configuration & Moosh](https://erseco.github.io/alpine-moodle/configuration/)
- [SQLite single-container mode](https://erseco.github.io/alpine-moodle/sqlite/)
- [Upgrading](https://erseco.github.io/alpine-moodle/upgrading/)
- [Troubleshooting](https://erseco.github.io/alpine-moodle/troubleshooting/)
- [FAQ](https://erseco.github.io/alpine-moodle/faq/)

## Contributing

Issues and pull requests are welcome: <https://github.com/erseco/alpine-moodle/issues>.

Documentation sources live under [`docs/`](docs/) and are built with [Zensical](https://zensical.org/) via the `docs.yml` GitHub Actions workflow.

## License

[MIT](LICENSE)
