# Upgrading

How to move between Moodle versions safely.

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

This covers **database schema** upgrades. It does **not** by itself swap out the Moodle PHP code — that depends on how you handle the `/var/www/html` volume.

## Upgrading the Moodle code

Your upgrade procedure depends on whether you persist `/var/www/html` as a named volume.

=== "Without `moodlehtml` volume"

    The container replaces the Moodle code on every start. Upgrading is just:

    ```bash
    docker compose pull
    docker compose up -d
    ```

    Trade-off: plugins and themes must be re-installed on every boot (use `POST_CONFIGURE_COMMANDS` with Moosh).

=== "With `moodlehtml` volume"

    Pinned Moodle code in a persistent volume will **not** be overwritten when you change the image tag ([#102](https://github.com/erseco/alpine-moodle/issues/102)). You will see logs like:

    ```
    No upgrade needed for the installed version 5.0.1 (Build: 20250609). Thanks for coming anyway!
    ```

    To actually upgrade:

    1. Back up the database, `moodledata`, and `moodlehtml` (see [Persistence & Volumes](persistence.md)).
    2. Put the site into maintenance mode (optional but recommended).
    3. Stop the stack and remove the `moodlehtml` volume:

        ```bash
        docker compose down
        docker volume rm <project>_moodlehtml
        ```

    4. Change the image tag in `docker-compose.yml`:

        ```yaml
        services:
          moodle:
            image: erseco/alpine-moodle:v5.0.2
        ```

    5. Bring it back up:

        ```bash
        docker compose pull
        docker compose up -d
        docker compose logs -f moodle
        ```

    6. Reinstall any custom plugins and themes.

!!! warning "Always back up first"
    Upgrades that involve removing volumes are irreversible. Take a database dump and a tarball of `moodledata` before you run `docker volume rm`.

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
