[![Docker Pulls](https://img.shields.io/docker/pulls/erseco/alpine-moodle.svg)](https://hub.docker.com/r/erseco/alpine-moodle/)
[![Docker image layers](https://images.microbadger.com/badges/image/erseco/alpine-moodle.svg)](https://microbadger.com/images/erseco/alpine-moodle)
![nginx 1.18.0](https://img.shields.io/badge/nginx-1.18-brightgreen.svg)
![php 8.0](https://img.shields.io/badge/php-8.0-brightgreen.svg)
![moodle-3.11.0](https://img.shields.io/badge/moodle-3.11.0-yellow)
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)

# Moodle on Alpine Linux
Moodle setup for Docker, build on [Alpine Linux](http://www.alpinelinux.org/).
The image is only +/- 70MB large.

Repository: https://github.com/erseco/alpine-moodle


* Built on the lightweight image https://github.com/erseco/alpine-php-webserver
* Very small Docker image size (+/-70MB)
* Uses PHP 8.0 for better performance, lower cpu usage & memory footprint
* Multi-arch support: 386, amd64, arm/v6, arm/v7, arm64, ppc64le, s390x
* Optimized for 100 concurrent users
* Optimized to only use resources when there's traffic (by using PHP-FPM's ondemand PM)
* Use of runit instead of supervisord to reduce memory footprint
* Configured cron to run as non-privileged user https://github.com/gliderlabs/docker-alpine/issues/381#issuecomment-621946699
* docker-compose sample with PostgreSQL
* Configuration via ENV variables
* Easily upgradable to new moodle versions
* The servers Nginx, PHP-FPM run under a non-privileged user (nobody) to make it more secure
* The logs of all the services are redirected to the output of the Docker container (visible with `docker logs -f <container name>`)
* Follows the KISS principle (Keep It Simple, Stupid) to make it easy to understand and adjust the image to your needs

## Usage

Start the Docker containers:

    docker-compose up

Login on the system using the provided credentials (ENV vars)

## Configuration
Define the ENV variables in docker-compose.yml file

| Variable Name               | Default              | Description                                                              |
|-----------------------------|----------------------|--------------------------------------------------------------------------|
| LANG                        | en_US.UTF-8          |                                                                          |
| LANGUAGE                    | en_US:en             |                                                                          |
| SITE_URL                    | http://localhost     | Sets the public site url                                                 |
| SSLPROXY                    | false                | Disable SSL proxy to avod site loop. Ej. Cloudfare                       |
| DB_TYPE                     | pgsql                | mysqli - pgsql - mariadb                                                 |
| DB_HOST                     | postgres             | DB_HOST Ej. db container name                                            |
| DB_PORT                     | 5432                 | Postgres=5432 - MySQL=3306                                               |
| DB_NAME                     | moodle               |                                                                          |
| DB_USER                     | moodle               |                                                                          |
| DB_PREFIX                   | mdl_                 | Database prefix. WARNING: don't use numeric values or moodle won't start |
| MOODLE_EMAIL                | user@example.com     |                                                                          |
| MOODLE_LANGUAGE             | en                   |                                                                          |
| MOODLE_SITENAME             | New-Site             |                                                                          |
| MOODLE_USERNAME             | moodleuser           |                                                                          |
| MOODLE_PASSWORD             | PLEASE_CHANGEME      |                                                                          |
| SMTP_HOST                   | smtp.gmail.com       |                                                                          |
| SMTP_PORT                   | 587                  |                                                                          |
| SMTP_USER                   | your_email@gmail.com |                                                                          |
| SMTP_PASSWORD               | your_password        |                                                                          |
| SMTP_PROTOCOL               | tls                  |                                                                          |
| MOODLE_MAIL_NOREPLY_ADDRESS | noreply@localhost    |                                                                          |
| MOODLE_MAIL_PREFIX          | [moodle]             |                                                                          |
| client_max_body_size        | 50M                  |                                                                          |
| post_max_size               | 50M                  |                                                                          |
| upload_max_filesize         | 50M                  |                                                                          |
| max_input_vars              | 1000                 |                                                                          |
