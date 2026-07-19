# Upgrading

How to move between Moodle versions safely.

!!! tip "Moving to Moodle 5.x? PHP 8.4 is available"
    Once you are on Moodle 5.x you can optionally switch to the PHP 8.4 image line by
    pulling the `-php84` tag (e.g. `v5.2.1-php84`). The default tags stay on PHP 8.3.
    See [PHP 8.4 (opt-in)](php84.md). Do **not** use `-php84` tags on Moodle 4.x.

## The basics

The image applies Moodle database upgrades automatically on startup unless you opt out:

```yaml
environment:
  AUTO_UPDATE_MOODLE: "true"   # default — runs admin/cli/upgrade.php at boot
```

Steps the container takes on start, when an existing installation is detected:

1. `admin/cli/maintenance.php --enable`
2. `admin/cli/upgrade.php --non-interactive --allow-unstable`
3. `admin/cli/maintenance.php --disable`

This covers **database schema** upgrades. Replacing the Moodle **PHP code** is handled separately by the version-aware code sync (`SYNC_MOODLE_CODE`, default `auto`) when you use a persistent `moodlehtml` volume ([#103](https://github.com/erseco/alpine-moodle/issues/103)).

## Upgrading the Moodle code

=== "With `moodlehtml` volume (auto sync)"

    On start, if the volume's Moodle `$version` differs from the image, the container:

    1. Preserves `config.php` and any `EXTRA_PLUGIN_PATHS`
    2. Rsyncs `/usr/src/moodle/` → `/var/www/html/` (`--delete` removes leftover core files)
    3. Restores the preserved paths
    4. Writes `.alpine-moodle-release`
    5. Continues with the usual `AUTO_UPDATE_MOODLE` / `upgrade.php` flow

    Operator steps:

    1. Back up the database and `moodledata` (see [Persistence & Volumes](persistence.md)).
    2. Change the image tag:

        ```yaml
        services:
          moodle:
            image: erseco/alpine-moodle:v5.0.2
        ```

    3. Pull and recreate:

        ```bash
        docker compose pull
        docker compose up -d
        docker compose logs -f moodle
        ```

        Look for a log line like `Moodle code sync: 2025041401.00 → 2025041402.00`.

    Custom plugins that live only on the volume should either be listed in `EXTRA_PLUGIN_PATHS` (e.g. `mod/attendance theme/space`) or reinstalled declaratively via `PLUGINS` / Moosh after each sync.

    To keep today's "volume always wins" behaviour (no automatic core refresh):

    ```yaml
    environment:
      SYNC_MOODLE_CODE: "never"
    ```

=== "Without `moodlehtml` volume"

    The container filesystem *is* the code. Upgrading is just:

    ```bash
    docker compose pull
    docker compose up -d
    ```

    Re-install plugins on every recreate with `PLUGINS` or `POST_CONFIGURE_COMMANDS` + Moosh.

=== "Legacy: wipe `moodlehtml`"

    Still valid if you want a clean tree:

    ```bash
    docker compose down
    docker volume rm <project>_moodlehtml
    docker compose pull
    docker compose up -d
    ```

!!! warning "Always back up first"
    Take a database dump and a tarball of `moodledata` before major upgrades. Code sync replaces files under `/var/www/html` (except `config.php` and `EXTRA_PLUGIN_PATHS`).

## Upgrading from Moodle < 5.1 to ≥ 5.1

Moodle 5.1 introduces a `public/` subdirectory for all web-exposed files ([MDL-83424](https://moodle.atlassian.net/browse/MDL-83424)). The container handles this automatically: when it detects `/var/www/html/public`, it rewrites the Nginx root and runs `composer install --no-dev --classmap-authoritative`.

Recommended upgrade flow:

1. Back up:
    - `config.php`
    - the `moodledata` volume
    - the database
2. Stop the stack and remove the `moodlehtml` volume (as above) — this is essential because the old 5.0 layout will otherwise confuse the new server config.
3. Change the image tag to a `5.1.x` (or newer) release.
4. Start the stack. The container installs the new code, serves it from `/public`, and runs `composer install`.
5. Reapply customisations (plugins, themes, `config.php` tweaks).

If you see *"`/var/www/html/vendor/composer` does not exist"* ([#117](https://github.com/erseco/alpine-moodle/issues/117)), the container has not finished bootstrapping yet. Watch `docker compose logs -f moodle` — the error is transient unless it recurs after 30+ seconds.

## Upgrading `moodledata` mounted from an older installation

Mounting an existing populated `moodledata` from a different image (for example migrating from Bitnami) can hit permission or layout mismatches ([#114](https://github.com/erseco/alpine-moodle/issues/114), [#105](https://github.com/erseco/alpine-moodle/issues/105)):

```
Data directory (/var/www/moodledata/) cannot be created by the installer.
```

Checklist:

- The volume must be writable by UID `65534` (`nobody`). Fix with `sudo chown -R 65534:65534 moodledata`.
- `config.php` on the new container must match the database — mount it alongside or inject it via `POST_CONFIGURE_COMMANDS`.
- The target Moodle version must be equal to or newer than the version that created the data.

For a full Bitnami migration see [#105](https://github.com/erseco/alpine-moodle/issues/105). In short: restore the database first, mount `moodledata` second, ensure the admin credentials in `config.php` match the database, then start the container.

## Disabling automatic upgrades

Set `AUTO_UPDATE_MOODLE=false` if you prefer to run `admin/cli/upgrade.php` manually:

```yaml
environment:
  AUTO_UPDATE_MOODLE: "false"
```

Manual upgrade:

```bash
docker compose exec moodle php admin/cli/maintenance.php --enable
docker compose exec moodle php admin/cli/upgrade.php --non-interactive
docker compose exec moodle php admin/cli/maintenance.php --disable
```

## Skipping versions

Moodle's upgrade scripts support skipping minor versions but you should not jump across multiple major versions in one go. Upgrade step by step (for example `4.1 → 4.5 → 5.0 → 5.1`), backing up between each step.
