# Quick Start

This page shows the fastest way to get a working Moodle instance.

!!! tip
    Always override `MOODLE_USERNAME` and `MOODLE_PASSWORD`. The defaults (`moodleuser` / `PLEASE_CHANGEME`) must never be used in a reachable environment.

## Option 1 — Single container (SQLite)

Great for local demos, evaluation, and CI smoke tests. **Not for production.**

```bash
docker run -d --name moodle \
  -p 80:8080 \
  -e MOODLE_DATABASE_TYPE=sqlite3 \
  -e MOODLE_USERNAME=admin \
  -e MOODLE_PASSWORD=ChangeMe123! \
  -e SITE_URL=http://localhost \
  -v moodledata:/var/www/moodledata \
  erseco/alpine-moodle
```

Then watch the logs until initialization finishes:

```bash
docker logs -f moodle
```

Open <http://localhost> and log in.

## Option 2 — Docker Compose with PostgreSQL

The recommended minimum for a persistent deployment:

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
      SITE_URL: http://localhost
      DB_TYPE: pgsql
      DB_HOST: postgres
      DB_NAME: moodle
      DB_USER: moodle
      DB_PASS: moodle
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

Start the stack:

```bash
docker compose up -d
docker compose logs -f moodle
```

The first boot installs the database schema and runs the Moodle CLI installer. Subsequent boots reuse the existing data.

## What to do next

- Put the container [behind a reverse proxy](reverse-proxy.md) for HTTPS.
- Review the [environment variables](environment-variables.md) to tune PHP limits, SMTP, Redis, etc.
- Read [Persistence & Volumes](persistence.md) before your first backup.
- When upgrading Moodle, follow [Upgrading](upgrading.md).
