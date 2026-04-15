# Configuration

Beyond the basic environment variables, the image offers several extension points for customising Moodle without rebuilding.

## Pre / post configuration hooks

Use `PRE_CONFIGURE_COMMANDS` and `POST_CONFIGURE_COMMANDS` to run arbitrary shell on every container start, before and after Moodle's configuration is applied.

```yaml
environment:
  PRE_CONFIGURE_COMMANDS: |
    echo "Running pre-configure step..."

  POST_CONFIGURE_COMMANDS: |
    moosh plugin-list
    moosh plugin-install --delete mod_attendance
    moosh plugin-install --delete theme_almondb
    php admin/cli/cfg.php --name=enableblogs --set=1
```

!!! tip "Idempotency"
    These hooks run **every time** the container starts. Use commands that can be re-run safely (the `--delete` flag on `moosh plugin-install` is recommended because of [a known Moosh bug](https://github.com/tmuras/moosh/issues/520) where the first install silently fails).

## Moosh CLI

[Moosh](https://github.com/tmuras/moosh) is bundled at `/opt/moosh` and exposed on the `PATH` as `moosh`.

```bash
docker compose exec moodle moosh plugin-list
docker compose exec moodle moosh plugin-install mod_attendance
docker compose exec moodle moosh user-create --password pass --email me@example.com \
  --firstname "Jane" --lastname "Doe" janedoe
docker compose exec moodle moosh course-backup 3
```

Full command reference: <https://moosh-online.com/commands/>

!!! warning "Memory limit errors from Moosh"
    Moosh plugin operations can exhaust PHP's memory limit on large plugins ([#119](https://github.com/erseco/alpine-moodle/issues/119)):

    ```
    PHP Fatal error:  Allowed memory size of 134217728 bytes exhausted in
    /opt/moosh/Moosh/Command/Generic/Plugin/PluginInstall.php on line 237
    ```

    Raise `memory_limit` in the container environment:

    ```yaml
    environment:
      memory_limit: 512M
    ```

## Moodle CLI

Everything under `admin/cli/` works as usual:

```bash
docker compose exec moodle php admin/cli/cfg.php --name=debug --set=32767
docker compose exec moodle php admin/cli/upgrade.php --non-interactive
docker compose exec moodle php admin/cli/purge_caches.php
docker compose exec moodle php admin/cli/maintenance.php --enable
```

## Redis sessions & caching

Set `REDIS_HOST` and (optionally) `REDIS_PASSWORD` / `REDIS_USER`:

```yaml
services:
  redis:
    image: redis:alpine

  moodle:
    environment:
      REDIS_HOST: redis
      # REDIS_PASSWORD: supersecret
      # REDIS_USER: moodle
```

On start the container runs `admin/cli/configure_redis.php` and writes the Redis session handler into `config.php`. Unset `REDIS_HOST` to go back to file sessions.

!!! note
    `REDIS_USER` requires Redis 6+ ACLs *and* `REDIS_PASSWORD`. The container fails fast if you set a user without a password.

## LDAP with custom certificates

The image ships with `php-ldap`. To trust a custom CA (for example your corporate LDAPS):

```bash
base64 -w0 my-ca.pem
```

Then pass the result as `MY_CERTIFICATES`:

```yaml
environment:
  MY_CERTIFICATES: "LS0tLS1CRUdJTi...LS0tLS0="
```

The value is decoded into `/etc/openldap/my-certificates/extra.pem` at startup and picked up by `openldap`'s client libraries.

See [#122](https://github.com/erseco/alpine-moodle/issues/122) for context.

## Running commands as root

The container runs as `nobody`. If you need to install packages for debugging, re-enter as root:

```bash
docker compose exec --user root moodle sh -c "apk update && apk add nano curl"
```

## Custom `config.php` tweaks

The startup script enforces the settings it manages (wwwroot, DB, proxy flags, Redis). You can still add custom `$CFG` values through `POST_CONFIGURE_COMMANDS` using sed or PHP, or by mounting a small snippet that `require`s at the end of `config.php`. Anything you write during runtime is lost on the next start unless it lives inside a persistent volume.

## Pinning a Moodle version at build time

```yaml
services:
  moodle:
    build:
      context: .
      args:
        MOODLE_VERSION: v5.0.2
```

Or use a pre-built tag:

```yaml
services:
  moodle:
    image: erseco/alpine-moodle:v5.0.2
```

Available Moodle tags: <https://github.com/moodle/moodle/tags>

## Disabling the internal cron

By default `runit` runs `admin/cli/cron.php` every 180 seconds inside the container ([#98](https://github.com/erseco/alpine-moodle/issues/98)). If you orchestrate cron externally (e.g. a Kubernetes CronJob), disable the internal loop:

```yaml
environment:
  RUN_CRON_TASKS: "false"
```

## Test scenario generator

```bash
docker compose exec moodle php admin/tool/generator/cli/runtestscenario.php
```

Or add it to `POST_CONFIGURE_COMMANDS` to seed a test site on every startup.
