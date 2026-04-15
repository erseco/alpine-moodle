# Environment Variables

Every setting exposed by `erseco/alpine-moodle`. Defaults come from the `Dockerfile` and are applied unless you override them in `docker run`, `docker-compose.yml`, or your orchestration tool.

## Site

| Variable           | Default              | Description |
|--------------------|----------------------|-------------|
| `SITE_URL`         | `http://localhost`   | Public URL of the site. Becomes `$CFG->wwwroot`. Must match what users type in the browser. |
| `MOODLE_SITENAME`  | `Dockerized_Moodle`  | Full name shown on the Moodle front page. |
| `MOODLE_LANGUAGE`  | `en`                 | Installer language. Sets `--lang` on `admin/cli/install.php`. |
| `LANG`             | `en_US.UTF-8`        | System locale. |
| `LANGUAGE`         | `en_US:en`           | System language fallback chain. |

## Admin user

| Variable           | Default           | Description |
|--------------------|-------------------|-------------|
| `MOODLE_USERNAME`  | `moodleuser`      | Initial admin username. |
| `MOODLE_PASSWORD`  | `PLEASE_CHANGEME` | Initial admin password. **Always override.** |
| `MOODLE_EMAIL`     | `user@example.com`| Admin email address. |

!!! warning
    If the container finds an existing install, these values are re-applied to the admin user on every start via `admin/cli/update_admin_user.php`. Keep them in sync with your secret store.

## Database — primary

| Variable                | Default   | Description |
|-------------------------|-----------|-------------|
| `DB_TYPE`               | `pgsql`   | `pgsql`, `mariadb`, `mysqli` or `sqlite3`. |
| `MOODLE_DATABASE_TYPE`  | *(empty)* | Optional override for `DB_TYPE`. Set to `sqlite3` to enable the single-container mode. |
| `DB_HOST`               | `postgres`| DB hostname (service name on the Docker network). |
| `DB_PORT`               | `5432`    | 5432 for PostgreSQL, 3306 for MariaDB/MySQL. |
| `DB_NAME`               | `moodle`  | Database name. |
| `DB_USER`               | `moodle`  | Database user. |
| `DB_PASS`               | `moodle`  | Database password. |
| `DB_PREFIX`             | `mdl_`    | Table prefix. Must be non-numeric. |
| `DB_SQLITE_PATH`        | `/var/www/moodledata/sqlite/moodle.sqlite` | SQLite file path. Must resolve inside `/var/www/moodledata/`. |
| `DB_FETCHBUFFERSIZE`    | *(empty)* | Set to `0` when using PgBouncer in *transaction* mode. |
| `DB_DBHANDLEOPTIONS`    | `false`   | Set to `true` with PgBouncer (pool modes that reject `SET` options). |

## Database — read replica (optional)

| Variable              | Default   | Description |
|-----------------------|-----------|-------------|
| `DB_HOST_REPLICA`     | *(empty)* | Enables the read-only replica if set. |
| `DB_PORT_REPLICA`     | *(empty)* | Falls back to `DB_PORT`. |
| `DB_USER_REPLICA`     | *(empty)* | Falls back to `DB_USER`. |
| `DB_PASS_REPLICA`     | *(empty)* | Falls back to `DB_PASS`. |

## Redis (optional)

| Variable         | Default   | Description |
|------------------|-----------|-------------|
| `REDIS_HOST`     | *(empty)* | When set, enables the Redis session handler and cache store. |
| `REDIS_PASSWORD` | *(empty)* | Redis password. |
| `REDIS_USER`     | *(empty)* | Redis 6+ ACL user. Requires `REDIS_PASSWORD` or the container aborts at startup. |

## Reverse proxy / TLS

| Variable       | Default | Description |
|----------------|---------|-------------|
| `REVERSEPROXY` | `false` | Set to `true` only if the site is intentionally served from multiple base URLs. |
| `SSLPROXY`     | `false` | Set to `true` when a reverse proxy terminates TLS. Trusts `X-Forwarded-Proto`. |
| `MY_CERTIFICATES` | `none` | Base64-encoded trusted certificate bundle installed into the LDAP truststore (`/etc/openldap/my-certificates/extra.pem`). Use `none` to disable. |

See [Reverse Proxy](reverse-proxy.md) for concrete examples.

## Email / SMTP

| Variable                       | Default                | Description |
|--------------------------------|------------------------|-------------|
| `SMTP_HOST`                    | `smtp.gmail.com`       | SMTP server hostname. |
| `SMTP_PORT`                    | `587`                  | SMTP server port. |
| `SMTP_USER`                    | `your_email@gmail.com` | SMTP username. |
| `SMTP_PASSWORD`                | `your_password`        | SMTP password. |
| `SMTP_PROTOCOL`                | `tls`                  | `tls`, `ssl` or empty. |
| `MOODLE_MAIL_NOREPLY_ADDRESS`  | `noreply@localhost`    | Used as `noreplyaddress`. |
| `MOODLE_MAIL_PREFIX`           | `[moodle]`             | Email subject prefix. |

## PHP / web server tuning

| Variable               | Default | Description |
|------------------------|---------|-------------|
| `client_max_body_size` | `50M`   | Nginx max request body size. |
| `post_max_size`        | `50M`   | PHP `post_max_size`. |
| `upload_max_filesize`  | `50M`   | PHP `upload_max_filesize`. |
| `max_input_vars`       | `5000`  | PHP `max_input_vars`. Keep high for Moodle course imports. |
| `memory_limit`         | `256M`  | PHP `memory_limit`. Increase to `512M` or more for big plugin installs / Moosh operations ([#119](https://github.com/erseco/alpine-moodle/issues/119)). |

## Operational

| Variable                 | Default | Description |
|--------------------------|---------|-------------|
| `AUTO_UPDATE_MOODLE`     | `true`  | If `false`, skip the automatic `admin/cli/upgrade.php` on container start. |
| `RUN_CRON_TASKS`         | `true`  | Set to `false` to disable the internal `runit`-managed cron loop. Useful when you run cron externally. |
| `DEBUG`                  | `false` | When `true`, enables Moodle `DEVELOPER` debug level and `debugdisplay`. |
| `PRE_CONFIGURE_COMMANDS` | *(empty)* | Shell commands run **before** Moodle configuration. |
| `POST_CONFIGURE_COMMANDS`| *(empty)* | Shell commands run **after** Moodle configuration (great for Moosh). |

## Build-time argument

| Build ARG        | Default | Description |
|------------------|---------|-------------|
| `MOODLE_VERSION` | `main`  | Upstream Moodle tag to install (e.g. `v5.0.2`, `v4.5.7`). `main` installs the current development branch. |

Full list of available Moodle tags: <https://github.com/moodle/moodle/tags>
