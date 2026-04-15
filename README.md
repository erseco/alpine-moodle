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

## Running Commands as Root

In certain situations, you might need to run commands as `root` within your Moodle container, for example, to install additional packages. You can do this using the `docker compose exec` command with the `--user root` option:

```bash
docker compose exec --user root moodle sh
```

Example — install an extra Alpine package for debugging:

```bash
docker compose exec --user root moodle sh -c "apk update && apk add nano curl"
```

## Configuration

Define the ENV variables in `docker-compose.yml`. The full reference with notes, grouping and defaults lives at <https://erseco.github.io/alpine-moodle/environment-variables/>.

| Variable Name               | Default              | Description |
|-----------------------------|----------------------|-------------|
| `LANG`                      | `en_US.UTF-8`        | System locale. |
| `LANGUAGE`                  | `en_US:en`           | System language fallback chain. |
| `SITE_URL`                  | `http://localhost`   | Public site URL. Must match what users type in the browser. |
| `REVERSEPROXY`              | `false`              | Set to `true` only if the site is intentionally served under multiple base URLs. See the [Reverse Proxy](https://erseco.github.io/alpine-moodle/reverse-proxy/) guide. |
| `SSLPROXY`                  | `false`              | Set to `true` when a reverse proxy terminates TLS. Trusts `X-Forwarded-Proto`. |
| `REDIS_HOST`                |                      | Hostname of the Redis instance (enables Redis sessions/cache). |
| `REDIS_PASSWORD`            |                      | Redis password. |
| `REDIS_USER`                |                      | Redis 6+ ACL user. Requires `REDIS_PASSWORD`. |
| `DB_TYPE`                   | `pgsql`              | `pgsql`, `mariadb`, `mysqli` or `sqlite3`. |
| `MOODLE_DATABASE_TYPE`      |                      | Optional override for `DB_TYPE`. Set to `sqlite3` to enable single-container dev/demo mode. |
| `DB_HOST`                   | `postgres`           | DB container name / hostname. |
| `DB_PORT`                   | `5432`               | Postgres=5432, MySQL/MariaDB=3306. |
| `DB_NAME`                   | `moodle`             | Database name. |
| `DB_USER`                   | `moodle`             | Database user. |
| `DB_PASS`                   | `moodle`             | Database password. |
| `DB_SQLITE_PATH`            | `/var/www/moodledata/sqlite/moodle.sqlite` | SQLite file path when using `sqlite3`. |
| `DB_FETCHBUFFERSIZE`        |                      | Set to `0` with PgBouncer in *transaction* mode. |
| `DB_DBHANDLEOPTIONS`        | `false`              | Set to `true` with PgBouncer pool modes that reject `SET` options. |
| `DB_HOST_REPLICA`           |                      | Read-only replica hostname. |
| `DB_PORT_REPLICA`           |                      | Replica port (falls back to `DB_PORT`). |
| `DB_USER_REPLICA`           |                      | Replica user (falls back to `DB_USER`). |
| `DB_PASS_REPLICA`           |                      | Replica password (falls back to `DB_PASS`). |
| `DB_PREFIX`                 | `mdl_`               | DB table prefix. Do not use numeric values. |
| `MY_CERTIFICATES`           | `none`               | Base64-encoded LDAP CA bundle. |
| `MOODLE_EMAIL`              | `user@example.com`   | Admin email. |
| `MOODLE_LANGUAGE`           | `en`                 | Installer language. |
| `MOODLE_SITENAME`           | `Dockerized_Moodle`  | Full site name shown on the front page. |
| `MOODLE_USERNAME`           | `moodleuser`         | Admin username. **Override on first boot.** |
| `MOODLE_PASSWORD`           | `PLEASE_CHANGEME`    | Admin password. **Override on first boot.** |
| `SMTP_HOST`                 | `smtp.gmail.com`     | SMTP server. |
| `SMTP_PORT`                 | `587`                | SMTP port. |
| `SMTP_USER`                 | `your_email@gmail.com` | SMTP username. |
| `SMTP_PASSWORD`             | `your_password`      | SMTP password. |
| `SMTP_PROTOCOL`             | `tls`                | `tls`, `ssl` or empty. |
| `MOODLE_MAIL_NOREPLY_ADDRESS` | `noreply@localhost` | No-reply address. |
| `MOODLE_MAIL_PREFIX`        | `[moodle]`           | Email subject prefix. |
| `AUTO_UPDATE_MOODLE`        | `true`               | Set to `false` to skip `admin/cli/upgrade.php` on container start. |
| `DEBUG`                     | `false`              | When `true`, enables Moodle `DEVELOPER` debug level. |
| `client_max_body_size`      | `50M`                | Nginx max request body size. |
| `post_max_size`             | `50M`                | PHP `post_max_size`. |
| `upload_max_filesize`       | `50M`                | PHP `upload_max_filesize`. |
| `max_input_vars`            | `5000`               | PHP `max_input_vars`. Keep high for Moodle course imports. |
| `memory_limit`              | `256M`               | PHP `memory_limit`. Increase if Moosh plugin installs run out of memory. |
| `PRE_CONFIGURE_COMMANDS`    |                      | Shell commands run before Moodle configuration. |
| `POST_CONFIGURE_COMMANDS`   |                      | Shell commands run after Moodle configuration (great for Moosh). |
| `RUN_CRON_TASKS`            | `true`               | Set to `false` to disable the internal `runit`-managed cron loop. |

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
