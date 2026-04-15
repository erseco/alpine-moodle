# Persistence & Volumes

Moodle stores state in three different places. Choosing which ones to persist determines how your backups work and how painful upgrades are.

## What each path contains

| Path inside the container | Contents | Should you persist it? |
|---------------------------|----------|------------------------|
| `/var/www/html`           | Moodle PHP code + `config.php` + installed plugins/themes | **Depends** — see below |
| `/var/www/moodledata`     | User-generated data: file uploads, sessions, cache, question attachments, backups | **Yes, always** |
| Database volume (Postgres / MariaDB) | Courses, users, grades, config, everything metadata | **Yes, always** |

## Recommended setup

```yaml
services:
  postgres:
    image: postgres:alpine
    volumes:
      - postgres:/var/lib/postgresql      # (1)

  moodle:
    image: erseco/alpine-moodle
    volumes:
      - moodledata:/var/www/moodledata    # (2)
      - moodlehtml:/var/www/html          # (3)

volumes:
  postgres:
  moodledata:
  moodlehtml:
```

1. Database files. Back up with `pg_dump`. See the note on PostgreSQL 18+ below.
2. Uploads, sessions, file storage. Back up with a cold copy or `tar`.
3. Moodle code, plugins, themes and `config.php`. See the upgrade tradeoff below.

## The `moodlehtml` tradeoff

Mounting `/var/www/html` as a named volume preserves installed plugins, custom themes, and `config.php` between container restarts. **The cost is that upgrading Moodle by changing the image tag alone does not work**, because the old code is kept on the volume ([#102](https://github.com/erseco/alpine-moodle/issues/102), [#103](https://github.com/erseco/alpine-moodle/issues/103)).

You have two patterns:

=== "Persistent `moodlehtml` (default)"

    Pros: plugins and themes survive restarts, `config.php` keeps customisations.

    Cons: to upgrade Moodle you need to remove the `moodlehtml` volume, start the new image, then re-apply plugins/themes. Always back up first.

    ```bash
    docker compose down
    docker volume rm <project>_moodlehtml
    docker compose pull
    docker compose up -d
    ```

=== "Ephemeral `moodlehtml`"

    Pros: upgrading Moodle is just `docker compose pull && docker compose up -d`.

    Cons: you must re-install plugins and re-apply theme customisations on every rebuild, or install them via `POST_CONFIGURE_COMMANDS` on every start.

    ```yaml
    services:
      moodle:
        volumes:
          - moodledata:/var/www/moodledata
          # no moodlehtml volume
    ```

    Pair this with idempotent Moosh commands:

    ```yaml
    environment:
      POST_CONFIGURE_COMMANDS: |
        moosh plugin-list
        moosh plugin-install --delete mod_attendance
    ```

!!! info "Future improvement"
    [#103](https://github.com/erseco/alpine-moodle/issues/103) tracks a finer-grained approach that would persist only `config.php`, themes and modules. Until that lands, pick the pattern that matches your risk tolerance.

## PostgreSQL 18+ volume path

Since PostgreSQL 18, the official `postgres` image expects the named volume at `/var/lib/postgresql`, not `/var/lib/postgresql/data` ([#133](https://github.com/erseco/alpine-moodle/issues/133)). If you pull `postgres:alpine` today you are on 18+.

```yaml
# Correct for postgres:18+ (and postgres:alpine today)
volumes:
  - postgres:/var/lib/postgresql
```

If you already have an existing volume created with the old path, follow the [`PGDATA` migration notes on Docker Hub](https://hub.docker.com/_/postgres) before switching. Mounting the old path on a new major version can silently overwrite your data.

## Permissions

The container runs as the non-privileged `nobody` user (UID `65534`). Named Docker volumes get the right ownership automatically. **Bind mounts do not** — if you mount a host directory, make sure it is writable by UID `65534`:

```bash
sudo chown -R 65534:65534 ./moodledata ./moodlehtml
```

See [#2](https://github.com/erseco/alpine-moodle/issues/2), [#6](https://github.com/erseco/alpine-moodle/issues/6), [#117](https://github.com/erseco/alpine-moodle/issues/117) for historical permission problems.

## Backups

Minimal backup plan for a PostgreSQL + named-volumes deployment:

```bash
# 1. Database
docker compose exec -T postgres pg_dump -U moodle moodle | gzip > moodle-db.sql.gz

# 2. Moodle data (uploads, sessions, file storage)
docker run --rm \
  -v <project>_moodledata:/data:ro \
  -v "$PWD":/backup \
  alpine tar czf /backup/moodledata.tar.gz -C /data .

# 3. (Optional) Moodle code + plugins + config.php
docker run --rm \
  -v <project>_moodlehtml:/html:ro \
  -v "$PWD":/backup \
  alpine tar czf /backup/moodlehtml.tar.gz -C /html .
```

Restore is the reverse: recreate the volumes, extract the tarballs back into them, and run `pg_restore`.

!!! tip
    Put the site into maintenance mode before taking a cold backup:

    ```bash
    docker compose exec moodle php admin/cli/maintenance.php --enable
    # ... run backup ...
    docker compose exec moodle php admin/cli/maintenance.php --disable
    ```
