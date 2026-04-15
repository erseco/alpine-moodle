# SQLite Single-Container Mode

`alpine-moodle` can run with an embedded SQLite database instead of PostgreSQL or MariaDB. The entire Moodle stack — web, PHP, database — fits in a single container with one mounted volume.

!!! danger "Development, demos and CI only"
    SQLite mode exists for fast local evaluation, ephemeral demos, and smoke tests in pipelines. **Do not run production workloads on SQLite.** Moodle's SQLite support is still experimental ([MDL-88218](https://moodle.atlassian.net/browse/MDL-88218)) and performance under concurrent load is not adequate for real use.

## When to use it

- You want to evaluate Moodle in under a minute.
- You are writing a plugin and need a disposable instance.
- Your CI pipeline boots Moodle to run automated tests against it.
- You are recording a tutorial or demo and do not want a database service.

For anything else, use [PostgreSQL or MariaDB](docker-compose.md).

## One-command boot

```bash
docker run -d --name moodle \
  -p 80:8080 \
  -e MOODLE_DATABASE_TYPE=sqlite3 \
  -e MOODLE_USERNAME=admin \
  -e MOODLE_PASSWORD=ChangeMe123! \
  -v moodledata:/var/www/moodledata \
  erseco/alpine-moodle
```

Open <http://localhost>, log in with `admin` / `ChangeMe123!`, done.

## Compose variant

```yaml
services:
  moodle:
    image: erseco/alpine-moodle
    restart: unless-stopped
    environment:
      MOODLE_DATABASE_TYPE: sqlite3
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: ChangeMe123!
      SITE_URL: http://localhost:8080
    ports:
      - "8080:8080"
    volumes:
      - moodledata:/var/www/moodledata

volumes:
  moodledata:
```

## How it works

When `MOODLE_DATABASE_TYPE=sqlite3` (or `DB_TYPE=sqlite3`), the startup script:

1. Skips the external database wait loop — no `nc` polling for `DB_HOST`.
2. Creates `/var/www/moodledata/sqlite/` if it does not exist and touches an empty `moodle.sqlite` file.
3. Writes a hand-crafted `config.php` that sets `dbtype=sqlite3`, `dblibrary=pdo` and points `dbname` at the SQLite file.
4. Runs `admin/cli/install_database.php` to create the schema.
5. Proceeds with the normal Moodle configuration (SMTP, Redis, cfg tweaks, cron).

The SQLite driver patches ([MDL-88218](https://moodle.atlassian.net/browse/MDL-88218)) are applied at **image build time** for supported Moodle versions:

| Moodle version | SQLite patch available? |
|----------------|-------------------------|
| `main` / `v5.2*` | Yes (from `ateeducacion/moodle` PR #1) |
| `v5.1*`          | Yes (PR #2) |
| `v5.0*`          | Yes (PR #3) |
| `v4.x` and older | **No** — the image will warn at build time and SQLite mode will not work |

## Customising the SQLite file location

The default is `/var/www/moodledata/sqlite/moodle.sqlite`. You can override it, but the resolved path must stay inside `/var/www/moodledata/` — the container refuses to run otherwise.

```yaml
environment:
  MOODLE_DATABASE_TYPE: sqlite3
  DB_SQLITE_PATH: /var/www/moodledata/custom/moodle.sqlite
```

The containing directory is created with mode `0700` and the database file with mode `0600`, both owned by the `nobody` user.

## Limitations

- **Concurrent writes**: SQLite is single-writer. Under simultaneous form submissions or imports you will see locking errors.
- **No replicas**: `DB_HOST_REPLICA` and related replica variables are ignored.
- **No external database tools**: you cannot connect `psql` or `mysql` to a SQLite file. Use the SQLite CLI or DB Browser for SQLite.
- **Upgrades**: the experimental driver is still moving upstream. Pinning an exact Moodle tag is strongly recommended when you use SQLite.

## Going from SQLite to PostgreSQL later

SQLite mode is one-way. To migrate a demo into a proper database you need to:

1. Dump courses and users with Moodle's course backup tools or `moosh course-backup`.
2. Recreate the stack with PostgreSQL or MariaDB.
3. Restore the course backups into the new instance.

There is no automatic schema conversion.
