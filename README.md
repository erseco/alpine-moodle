# Moodle on Alpine Linux

[![Docker Pulls](https://img.shields.io/docker/pulls/erseco/alpine-moodle.svg)](https://hub.docker.com/r/erseco/alpine-moodle/)
![Docker Image Size](https://img.shields.io/docker/image-size/erseco/alpine-moodle)
![nginx 1.26](https://img.shields.io/badge/nginx-1.26-brightgreen.svg)
![php 8.3](https://img.shields.io/badge/php-8.3-brightgreen.svg)
![moodle-4.4.0](https://img.shields.io/badge/moodle-4.4-yellow)
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)
<a href="https://www.buymeacoffee.com/erseco"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" height="20px"></a>

Moodle setup for Docker, build on [Alpine Linux](http://www.alpinelinux.org/).
The image is only +/- 70MB large.

Repository: https://github.com/erseco/alpine-moodle


* Built on the lightweight image https://github.com/erseco/alpine-php-webserver
* Very small Docker image size (+/-70MB)
* Uses PHP 8.3 for better performance, lower cpu usage & memory footprint
* Support for HA installations: php-redis, php-ldap (also with self-signed certs)
* Multi-arch support: 386, amd64, arm/v6, arm/v7, arm64, ppc64le, s390x
* Optimized for 100 concurrent users
* Optimized to only use resources when there's traffic (by using PHP-FPM's ondemand PM)
* Use of runit instead of supervisord to reduce memory footprint
* Configured cron to run as non-privileged user https://github.com/gliderlabs/docker-alpine/issues/381#issuecomment-621946699
* docker-compose sample with PostgreSQL and Redis
* Configuration via ENV variables
* Easily upgradable to new moodle versions
* The servers Nginx, PHP-FPM run under a non-privileged user (nobody) to make it more secure
* The logs of all the services are redirected to the output of the Docker container (visible with `docker logs -f <container name>`)
* Follows the KISS principle (Keep It Simple, Stupid) to make it easy to understand and adjust the image to your needs

## Usage

Start the Docker containers:

    docker-compose up

Login on the system using the provided credentials (ENV vars)

## Running Commands as Root

In certain situations, you might need to run commands as `root` within your Moodle container, for example, to install additional packages. You can do this using the `docker-compose exec` command with the `--user root` option. Here's how:

```bash
docker-compose exec --user root moodle sh
```

## Configuration
Define the ENV variables in docker-compose.yml file

| Variable Name               | Default              | Description                                                                                    |
|-----------------------------|----------------------|------------------------------------------------------------------------------------------------|
| LANG                        | en_US.UTF-8          |                                                                                                |
| LANGUAGE                    | en_US:en             |                                                                                                |
| SITE_URL                    | http://localhost     | Sets the public site url                                                                       |
| REVERSEPROXY                | false                | Enable when setting up advanced reverse proxy |
| SSLPROXY                    | false                | Disable SSL proxy to avoid site loop. Ej. Cloudfare                                            |
| REDIS_HOST                  | redis                |                                          |
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
