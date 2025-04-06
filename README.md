# Moodle on Alpine Linux

[![Docker Pulls](https://img.shields.io/docker/pulls/erseco/alpine-moodle.svg)](https://hub.docker.com/r/erseco/alpine-moodle/)
![Docker Image Size](https://img.shields.io/docker/image-size/erseco/alpine-moodle)
![nginx 1.26](https://img.shields.io/badge/nginx-1.26-brightgreen.svg)
![php 8.3](https://img.shields.io/badge/php-8.3-brightgreen.svg)
![moodle](https://img.shields.io/badge/moodle-configurable-yellow)
![moosh 1.27](https://img.shields.io/badge/moosh-1.27-orange)
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Build Status](https://github.com/erseco/alpine-moodle/actions/workflows/build.yml/badge.svg)

A lightweight Moodle Docker image built on [Alpine Linux](https://alpinelinux.org/). (~100MB)

Repository: https://github.com/erseco/alpine-moodle

**Key Features**

- Built on the lightweight image https://github.com/erseco/alpine-php-webserver
- Compact Docker image size (~100MB)
- Uses PHP 8.3 FPM for better performance, lower cpu usage & memory footprint
- Includes Composer and [Moosh CLI](https://github.com/tmuras/moosh)
- Support for HA installations: php-redis, php-ldap (also with self-signed certs)
- Multi-arch support: 386, amd64, arm/v6, arm/v7, arm64, ppc64le, s390x
- Optimized for 100 concurrent users
- Optimized to only use resources when there's traffic (by using PHP-FPM's ondemand PM)
- Uses `runit` instead of `supervisord` to reduce memory footprint
- Cron jobs run every 180 seconds by runit
- Sample `docker compose.yml` with PostgreSQL and Redis
- Configuration via `ENV` variables
- Services (`Nginx`, `PHP-FPM` run under a non-privileged user (`nobody`) for improved security
- Logs are sent to container's STDOUT (`docker logs -f <container>`)
- Extensible via pre/post configuration hooks  
- Follows the KISS principle (Keep It Simple, Stupid) to make it easy to understand and adjust the image to your needs


## Usage

**From Docker Hub:**
```bash
docker compose up
```
> Log in using the credentials defined by environment variables.

**From GHCR:**
```yaml
services:
  moodle:
    image: ghcr.io/erseco/alpine-moodle
    # rest of your config
```

## Running Commands as Root

In certain situations, you might need to run commands as `root` within your Moodle container, for example, to install additional packages. You can do this using the `docker compose exec` command with the `--user root` option. Here's how:

```bash
docker compose exec --user root moodle sh
```

## Configuration
Define the ENV variables in docker compose.yml file

| Variable Name               | Default              | Description                                                                                    |
|-----------------------------|----------------------|------------------------------------------------------------------------------------------------|
| LANG                        | en_US.UTF-8          |                                                                                                |
| LANGUAGE                    | en_US:en             |                                                                                                |
| SITE_URL                    | http://localhost     | Sets the public site url                                                                       |
| REVERSEPROXY                | false                | Enable when setting up advanced reverse proxy |
| SSLPROXY                    | false                | Disable SSL proxy to avoid site loop. Ej. Cloudfare                                            |
| REDIS_HOST                  |                      | Set the host of the redis instance. Ej. redis                                         |
| DB_TYPE                     | pgsql                | mysqli - pgsql - mariadb                                                                       |
| DB_HOST                     | postgres             | DB_HOST Ej. db container name                                                                  |
| DB_PORT                     | 5432                 | Postgres=5432 - MySQL=3306                                                                     |
| DB_NAME                     | moodle               |                                                                                                |
| DB_USER                     | moodle               |                                                                                                |
| DB_FETCHBUFFERSIZE          |                      | Set to 0 if using PostgresSQL poolers like PgBouncer in 'transaction' mode                     |
| DB_DBHANDLEOPTIONS          | false                | Set to true if using PostgresSQL poolers like PgBouncer which does not support sending options |
| DB_HOST_REPLICA             |                      | Database hostname of the read-only replica database                                            |
| DB_PORT_REPLICA             |                      | Database port of replica, left it empty to be same as DB_PORT                                  |
| DB_USER_REPLICA             |                      | Database login username of replica, left it empty to be same as DB_USER                        |
| DB_PASS_REPLICA             |                      | Database login password of replica, left it empty to be same as DB_PASS                        |
| DB_PREFIX                   | mdl_                 | Database prefix. WARNING: don't use numeric values or moodle won't start                       |
| MY_CERTIFICATES             | none                 | Trusted LDAP certificate or chain getting through base64 encode                                |
| MOODLE_EMAIL                | user@example.com     |                                                                                                |
| MOODLE_LANGUAGE             | en                   |                                                                                                |
| MOODLE_SITENAME             | New-Site             |                                                                                                |
| MOODLE_USERNAME             | moodleuser           |                                                                                                |
| MOODLE_PASSWORD             | PLEASE_CHANGEME      |                                                                                                |
| SMTP_HOST                   | smtp.gmail.com       |                                                                                                |
| SMTP_PORT                   | 587                  |                                                                                                |
| SMTP_USER                   | your_email@gmail.com |                                                                                                |
| SMTP_PASSWORD               | your_password        |                                                                                                |
| SMTP_PROTOCOL               | tls                  |                                                                                                |
| MOODLE_MAIL_NOREPLY_ADDRESS | noreply@localhost    |                                                                                                |
| MOODLE_MAIL_PREFIX          | [moodle]             |                                                                                                |
| AUTO_UPDATE_MOODLE          | true                 | Set to false to disable performing update of Moodle (e.g. plugins) at docker start             |
| DEBUG                       | false                |                                                                                                |
| client_max_body_size        | 50M                  |                                                                                                |
| post_max_size               | 50M                  |                                                                                                |
| upload_max_filesize         | 50M                  |                                                                                                |
| max_input_vars              | 5000                 |                                                                                                |
| PRE_CONFIGURE_COMMANDS      |                      | Commands to run before starting the configuration                                              |
| POST_CONFIGURE_COMMANDS     |                      | Commands to run after finished the configuration                                               |

## Minimal docker-compose.yml example

```yaml
---
services:
  postgres:
    image: postgres:alpine
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=moodle
      - POSTGRES_USER=moodle
      - POSTGRES_DB=moodle
    volumes:
      - postgres:/var/lib/postgresql/data
  moodle:
    image: erseco/alpine-moodle
    restart: unless-stopped
    environment:
      MOODLE_USERNAME: moodleuser
      MOODLE_PASSWORD: PLEASE_CHANGEME
    ports:
      - 80:8080
    volumes:
      - moodledata:/var/www/moodledata
      - moodlehtml:/var/www/html
    depends_on:
      - postgres
volumes:
  postgres: null
  moodledata: null
  moodlehtml: null
```

## Advanced Features

### 1. Using Moosh CLI

This image includes [Moosh](https://github.com/tmuras/moosh) — a powerful CLI tool to manage Moodle installations. You can invoke any Moosh command using:

```bash
docker compose exec moodle moosh <command>
```

Examples:

#### Upgrade plugin list (required to install)
```bash
docker compose exec moodle moosh plugin-list
```

#### Install a Plugin by Name
```bash
docker compose exec moodle moosh plugin-install mod_attendance
```

> You can force the installation of unsupported plugins with the `--force` option. 

> NOTE:[There is a bug in moosh and the first installation is not working](https://github.com/tmuras/moosh/issues/520), so we recommend calling again the install function with the `--delete` flag option or use the `module-reinstall` option: eg: `docker compose exec moodle moosh plugin-install --delete theme_almondb` or call `docker compose exec moodle moosh module-reinstall theme_almondb`
#### Backup a Course

Backup course with provided id. By default, logs and grade histories are excluded.

Example: Backup course id=3 into default .mbz file in `/opt/moosh/` directory from container:

```bash
docker compose exec moodle moosh course-backup 3
```

#### Create a User

Create a new Moodle user. Provide one or more arguments to create one or more users.

Example: create user "testuser" with the all the optional values


```bash
docker compose exec moodle moosh user-create --password pass --email me@example.com --digest 2 --city Valverde --country ES --institution "IES Garoé" --department "Technology" --firstname "first name" --lastname name testuser
```

#### Delete a User

Delete user(s) from Moodle. Provide one or more usernames as arguments.
Example: delete user testuser

```bash
docker compose exec moodle moosh user-delete testuser
```

These examples can be included directly in `POST_CONFIGURE_COMMANDS` to automate plugin installation, backups, or any Moosh-supported functionality.

Using Moosh promotes the DRY (Don't Repeat Yourself) principle and leverages a powerful toolset for Moodle administration.

For the full list of commands, visit: https://moosh-online.com/commands/


### 2. Pre/Post Configuration Hooks

You can define commands to be executed before and after the configuration of Moodle using the `PRE_CONFIGURE_COMMANDS` and `POST_CONFIGURE_COMMANDS` environment variables. These can be useful for tasks such as installing additional packages or running scripts.

```yaml
environment:
  PRE_CONFIGURE_COMMANDS: "cat config-dist.php"
  POST_CONFIGURE_COMMANDS: |
    moosh plugin-list
    moosh plugin-install --delete theme_almondb
    moosh plugin-install --delete theme_almondb
```

### 3. Specifying a Moodle Version

Calling `docker compose build` uses the latest version of Moodle from the main branch. If you need to use a specific Moodle version, you can specify it using the `MOODLE_VERSION` build argument.

To use a specific version, edit the build section for the moodle service in your docker compose.yml file:

```yaml
moodle:
  image: erseco/alpine-moodle
  build:
    context: .
    args:
      MOODLE_VERSION: v4.5.3  # Replace with your desired version
```
You can find the list of available version tags at: https://github.com/moodle/moodle/tags


### 4. Enabling Test Scenario Generator

Moodle includes a tool to create [test scenarios](https://moodledev.io/general/development/tools/generator#create-a-testing-scenario-using-behat-generators) under `Admin > Development > Create testing scenarios`. To enable it, run the following command, or add it in `POST_CONFIGURE_COMMANDS`:

```bash
php admin/tool/generator/cli/runtestscenario.php
```

This tool allows generating all necessary elements for manual testing using `.feature` file syntax.

## Maintenance Tips

**Install Additional Alpine Packages (as root):**
```bash
docker compose exec --user root moodle sh -c "apk update && apk add nano"
```

**Manual Database Upgrade:**
```bash
docker compose exec moodle php admin/cli/upgrade.php
```

**Access Logs:**
```bash
docker compose logs -f moodle
```


