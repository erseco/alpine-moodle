# Moodle on Alpine Linux
Moodle setup for Docker, build on [Alpine Linux](http://www.alpinelinux.org/).
The image is only +/- 35MB large.

Repository: https://github.com/erseco/alpine-moodle


* Built on the lightweight image https://github.com/erseco/alpine-php7-webserver
* Very small Docker image size (+/-70MB)
* Uses PHP 7.3 for better performance, lower cpu usage & memory footprint
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

[![Docker Pulls](https://img.shields.io/docker/pulls/erseco/alpine-moodle.svg)](https://hub.docker.com/r/erseco/alpine-moodle/)
[![Docker image layers](https://images.microbadger.com/badges/image/erseco/alpine-moodle.svg)](https://microbadger.com/images/erseco/alpine-moodle)
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)

## Usage

Start the Docker containers:

    docker-compose up

Login on the system using the provided credentials (ENV vars)

## Configuration
Define the ENV variables in docker-compose.yml file


```
    LANG="en_US.UTF-8"
    LANGUAGE="en_US:en"
    SITE_URL="http://localhost"
    DB_TYPE="pgsql"
    DB_HOST="postgres"
    DB_PORT="5432"
    DB_NAME="moodle"
    DB_USER="moodle"
    DB_PASS="moodle"
    DB_PREFIX="mdl_"
    MOODLE_EMAIL="user@example.com"
    MOODLE_LANGUAGE="en"
    MOODLE_SITENAME="New Site"
    MOODLE_USERNAME="moodleuser"
    MOODLE_PASSWORD="PLEASE_CHANGE_ME"
    SMTP_HOST=smtp.gmail.com
    SMTP_PORT=587
    SMTP_USER=your_email@gmail.com
    SMTP_PASSWORD=your_password \
    SMTP_PROTOCOL=tls
    MOODLE_MAIL_NOREPLY_ADDRESS="noreply@localhost"
    MOODLE_MAIL_PREFIX="[moodle]"
```

