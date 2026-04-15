# Docker Compose Examples

Practical `docker-compose.yml` stacks for common deployment shapes. Pick the one that matches your environment and adapt the passwords, domain, and ports.

## Minimal local deployment

Single PostgreSQL, no Redis, no reverse proxy. Good for evaluation and local development.

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

## Persistent deployment with Redis

Adds Redis session handling for better performance and shared sessions across replicas.

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

  redis:
    image: redis:alpine
    restart: unless-stopped

  moodle:
    image: erseco/alpine-moodle
    restart: unless-stopped
    environment:
      SITE_URL: https://moodle.example.com
      DB_HOST: postgres
      DB_USER: moodle
      DB_PASS: moodle
      DB_NAME: moodle
      REDIS_HOST: redis
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: ChangeMe123!
      MOODLE_SITENAME: "My Moodle"
      MOODLE_EMAIL: admin@example.com
      SSLPROXY: "true"
    ports:
      - "8080:8080"
    volumes:
      - moodledata:/var/www/moodledata
      - moodlehtml:/var/www/html
    depends_on:
      - postgres
      - redis

volumes:
  postgres:
  moodledata:
  moodlehtml:
```

## Deployment behind a reverse proxy

The reverse proxy terminates TLS and forwards to Moodle over the internal Docker network. The container does **not** need to expose any port to the host.

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
      SITE_URL: https://moodle.example.com
      SSLPROXY: "true"
      REVERSEPROXY: "false"
      DB_HOST: postgres
      DB_USER: moodle
      DB_PASS: moodle
      DB_NAME: moodle
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: ChangeMe123!
    volumes:
      - moodledata:/var/www/moodledata
      - moodlehtml:/var/www/html
    networks:
      - proxy
      - default
    depends_on:
      - postgres

volumes:
  postgres:
  moodledata:
  moodlehtml:

networks:
  proxy:
    external: true
```

See [Reverse Proxy](reverse-proxy.md) for complete examples for Traefik, Nginx, Nginx Proxy Manager, Apache and Caddy.

## MariaDB instead of PostgreSQL

```yaml
services:
  mariadb:
    image: mariadb:lts
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: rootpw
      MARIADB_DATABASE: moodle
      MARIADB_USER: moodle
      MARIADB_PASSWORD: moodle
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --innodb-file-per-table=1
    volumes:
      - mariadb:/var/lib/mysql

  moodle:
    image: erseco/alpine-moodle
    restart: unless-stopped
    environment:
      DB_TYPE: mariadb
      DB_HOST: mariadb
      DB_PORT: 3306
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
      - mariadb

volumes:
  mariadb:
  moodledata:
  moodlehtml:
```

!!! note "Moodle requires specific MySQL/MariaDB settings"
    Moodle expects `utf8mb4`, a large row format and `innodb_file_per_table`. The command overrides above cover the most common requirements.

## SQLite single-container mode

```yaml
services:
  moodle:
    image: erseco/alpine-moodle
    restart: unless-stopped
    environment:
      MOODLE_DATABASE_TYPE: sqlite3
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: ChangeMe123!
    ports:
      - "8080:8080"
    volumes:
      - moodledata:/var/www/moodledata

volumes:
  moodledata:
```

See the [SQLite Mode](sqlite.md) page for the full story.

## Pinning a Moodle version

You can run any Moodle tag available in the upstream repository:

```yaml
services:
  moodle:
    image: erseco/alpine-moodle:v5.0.2
```

Or build the image yourself for a specific Moodle version:

```yaml
services:
  moodle:
    build:
      context: .
      args:
        MOODLE_VERSION: v5.0.2
```

Available tags: <https://github.com/moodle/moodle/tags>
