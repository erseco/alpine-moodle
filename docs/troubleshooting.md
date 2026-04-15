# Troubleshooting

The most common problems users run into, mined from GitHub Issues. Each entry links to the original report so you can dig deeper.

## CSS is missing / site looks broken

**Symptoms**: Moodle renders with plain HTML, no styling, images fail to load. Browser console shows mixed-content blocks or 404s on `/theme/yui_combo.php` etc.

**Cause**: `$CFG->wwwroot` does not match the URL the browser uses. This is almost always a reverse-proxy / `SITE_URL` mismatch. Related: [#21](https://github.com/erseco/alpine-moodle/issues/21), [#101](https://github.com/erseco/alpine-moodle/issues/101).

**Fix**:

```yaml
environment:
  SITE_URL: https://moodle.example.com   # the PUBLIC URL
  SSLPROXY: "true"                       # proxy terminates TLS
  REVERSEPROXY: "false"
```

Then restart the container and purge caches:

```bash
docker compose restart moodle
docker compose exec moodle php admin/cli/purge_caches.php
```

## `ERR_TOO_MANY_REDIRECTS`

**Cause**: Moodle thinks the connection is HTTP while the browser uses HTTPS, so it keeps redirecting to its canonical `wwwroot`. Related: [#15](https://github.com/erseco/alpine-moodle/issues/15).

**Fix**:

- Set `SSLPROXY=true`.
- Make sure your proxy forwards `X-Forwarded-Proto: https`.
- Set `SITE_URL` to the HTTPS URL.

## "Reverse proxy enabled so the server cannot be accessed directly"

**Cause**: `REVERSEPROXY=true` on a single-URL deployment. Moodle refuses direct access when it expects multiple base URLs. Related: [#137](https://github.com/erseco/alpine-moodle/issues/137).

**Fix**: set `REVERSEPROXY=false`. Keep `SSLPROXY=true`.

## 502 Bad Gateway behind Traefik

**Cause**: Traefik is pointing at the wrong port. The container listens on **8080**, not 80. Related: [#61](https://github.com/erseco/alpine-moodle/issues/61).

**Fix**:

```yaml
labels:
  - "traefik.http.services.moodle.loadbalancer.server.port=8080"
```

## "Real client IPs" are all the Docker gateway

**Cause**: The proxy is not forwarding `X-Forwarded-For`, or a middle hop is stripping it. Related: [#11](https://github.com/erseco/alpine-moodle/issues/11), [#137](https://github.com/erseco/alpine-moodle/issues/137).

**Fix**: Make the outermost proxy set `X-Forwarded-For` to the real client IP. Each downstream hop must append (not replace) it. Confirm by running `docker compose exec moodle tail -f /var/log/nginx/access.log` and watching the IP in the request line.

Cloudflare users can use `CF-Connecting-IP` instead.

## `Allowed memory size exhausted` when installing a plugin with Moosh

**Cause**: Default `memory_limit` (256M) is too low for some plugins. Related: [#119](https://github.com/erseco/alpine-moodle/issues/119).

**Fix**:

```yaml
environment:
  memory_limit: 512M
```

Restart the container. Then re-run the Moosh command — don't forget the `--delete` flag to work around the known Moosh install bug:

```bash
docker compose exec moodle moosh plugin-install --delete theme_almondb
```

## `pluglist.php ... HTTP/1.1 403 Forbidden`

**Cause**: Transient issue with `download.moodle.org` hitting Moosh's plugin list endpoint. Related: [#95](https://github.com/erseco/alpine-moodle/issues/95).

**Fix**:

```bash
docker compose exec moodle rm -f /tmp/.moosh/plugins.json
docker compose exec moodle moosh plugin-list
```

Retry after a few minutes if it keeps 403'ing.

## PostgreSQL connection refused on a custom port

**Cause**: `DB_PORT` is not being passed through. Make sure it is a string (quoted) in YAML. Related: [#78](https://github.com/erseco/alpine-moodle/issues/78).

**Fix**:

```yaml
environment:
  DB_TYPE: pgsql
  DB_HOST: postgres.example.com
  DB_PORT: "5060"
  DB_NAME: moodle
  DB_USER: moodle
  DB_PASS: moodle
```

## Data loss after `docker compose down && up` with PostgreSQL 18+

**Cause**: Recent `postgres:alpine` images (18+) expect the named volume at `/var/lib/postgresql`, not `/var/lib/postgresql/data`. Mounting the wrong path makes Postgres create an *anonymous* volume and Moodle starts from scratch. Related: [#133](https://github.com/erseco/alpine-moodle/issues/133).

**Fix**:

```yaml
volumes:
  - postgres:/var/lib/postgresql
```

Follow the [`PGDATA` migration notes](https://hub.docker.com/_/postgres) if you already have an old volume.

## "Data directory (/var/www/moodledata/) cannot be created by the installer"

**Cause**: The mounted `moodledata` is not writable by UID `65534` (`nobody`), or you are reusing a populated `moodledata` from another image with mismatched permissions. Related: [#114](https://github.com/erseco/alpine-moodle/issues/114), [#2](https://github.com/erseco/alpine-moodle/issues/2).

**Fix**:

```bash
sudo chown -R 65534:65534 ./moodledata
```

For bind mounts only. Named Docker volumes get the right ownership automatically.

## Plugins disappear after upgrading

**Cause**: The `moodlehtml` volume was removed during the upgrade. Plugins live inside `/var/www/html/...`. Related: [#9](https://github.com/erseco/alpine-moodle/issues/9), [#103](https://github.com/erseco/alpine-moodle/issues/103).

**Fix**: Reinstall via `POST_CONFIGURE_COMMANDS` so they are reapplied automatically:

```yaml
environment:
  POST_CONFIGURE_COMMANDS: |
    moosh plugin-list
    moosh plugin-install --delete mod_attendance
```

## Upgrade seems to do nothing — "No upgrade needed"

**Cause**: Old Moodle code is still in the `moodlehtml` volume because you changed the image tag without clearing it. Related: [#102](https://github.com/erseco/alpine-moodle/issues/102).

**Fix**: Back up, then remove the `moodlehtml` volume and restart:

```bash
docker compose down
docker volume rm <project>_moodlehtml
docker compose pull
docker compose up -d
```

See [Upgrading](upgrading.md) for the full procedure.

## LDAP says the PHP module is missing

**Cause**: Old image tag. `php-ldap` is bundled in current releases. Related: [#122](https://github.com/erseco/alpine-moodle/issues/122).

**Fix**: `docker compose pull` to update to a current tag. If you use a custom LDAP CA, pass it via `MY_CERTIFICATES` (base64-encoded PEM).

## `/var/www/html/vendor/composer does not exist`

**Cause**: Moodle 5.1+ requires `composer install` to run inside the container on first start. If you stopped the container during this step or mounted an incomplete `/var/www/html`, the vendor directory is missing. Related: [#117](https://github.com/erseco/alpine-moodle/issues/117).

**Fix**: Let the container start fully and watch the logs. If it persists, enter the container and run:

```bash
docker compose exec moodle composer install --no-dev --classmap-authoritative \
  --working-dir=/var/www/html
```

## Cron-related errors ("exit status 127")

**Cause**: Historically `php` was missing from the cron service environment. Related: [#18](https://github.com/erseco/alpine-moodle/issues/18).

**Fix**: Update to a current image. If you want to disable the internal cron entirely, set `RUN_CRON_TASKS=false` and schedule `admin/cli/cron.php` externally.

## `config.php writable` warning

**Cause**: `config.php` is intentionally made read-only after install for security. Moodle surfaces this as a warning in the admin dashboard. Related: [#12](https://github.com/erseco/alpine-moodle/issues/12).

**Fix**: This is by design and can be safely ignored. It is not an error.

## Where to find Moodle debug output

Enable developer debug mode in the container:

```yaml
environment:
  DEBUG: "true"
```

Then read logs with `docker compose logs -f moodle` and browse the site — errors appear both in the logs and rendered in the page. Related: [#25](https://github.com/erseco/alpine-moodle/issues/25).
