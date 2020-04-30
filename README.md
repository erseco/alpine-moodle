# Moodle on Alpine Linux
Moodle setup for Docker, build on [Alpine Linux](http://www.alpinelinux.org/).
The image is only +/- 35MB large.

Repository: https://github.com/erseco/alpine-moodle


* Built on the lightweight image https://github.com/erseco/alpine-php7-webserver
* Very small Docker image size (+/-35MB)
* Uses PHP 7.3 for better performance, lower cpu usage & memory footprint
* Optimized for 100 concurrent users
* Optimized to only use resources when there's traffic (by using PHP-FPM's ondemand PM)
* Use of runit instead of supervisord to reduce memory footprint
* Configured cron job
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
    DB_COLLATION="utf8mb4_unicode_ci"
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





















# [dimaip/docker-neos-apline](https://hub.docker.com/r/dimaip/docker-neos-alpine/) &middot; [![](https://images.microbadger.com/badges/image/dimaip/docker-neos-alpine.svg)](https://microbadger.com/images/dimaip/docker-neos-alpine "Neos Alpine") [![](https://images.microbadger.com/badges/version/dimaip/docker-neos-alpine.svg)](https://microbadger.com/images/dimaip/docker-neos-alpine "Neos Alpine") [![](https://circleci.com/gh/psmb/docker-neos-alpine.svg?style=shield)](https://circleci.com/gh/psmb/docker-neos-alpine/)

[**Image info**](https://microbadger.com/images/dimaip/docker-neos-alpine)

Opinionated [Neos CMS](https://neos.io) docker image based on **Alpine** linux with **nginx** + **php-fpm 7.2** + **s6** process manager, packing everything needed for development and production usage of Neos in under 100mb.

The image does a few things:
1. Automatically install and provision a Neos website, based on environment vars documented below
2. Pack a few useful things like XDEBUG integration, git, beard etc.
3. ~~Be ready to be used in production and serve as a rolling deployment target with this Ansible script https://github.com/psmb/ansible-deploy~~ (I gave up on this deployment method, use 2.x version of this image if you need it, but rather consider full conatiner deployment)

Check out [this shell script](https://github.com/psmb/docker-neos-alpine/blob/master/root/etc/cont-init.d/10-init-neos) to see what exactly this image can do for you.

## Usage

This image supports following environment variable for automatically configuring Neos at container startup:

| Docker env variable | Description |
|---------|-------------|
|REPOSITORY_URL|Link to Neos website distribution|
|REPOSITORY_WWW|/data/www/ local path where to clone repo, default is `.`|
|REPOSITORY_CMD| overrides git clone command|
|VERSION|Git repository branch, commit SHA or release tag, defaults to `master`|
|SITE_PACKAGE|Neos website package with exported website data to be imported, optional|
|ADMIN_PASSWORD|If set, would create a Neos `admin` user with such password, optional|
|~~BASE_URI~~|2.x image only. If set, set the `baseUri` option in Settings.yaml, optional|
|DONT_PUBLISH_PERSISTENT| Don't publish persistent assets on init. Needed e.g. for cloud resources.|
|AWS_BACKUP_ARN|Automatically import the database from `${AWS_RESOURCES_ARN}db.sql` on the first container launch. Requires `AWS_ACCESS_KEY`, `AWS_SECRET_ACCESS_KEY` and `AWS_ENDPOINT` (optional, for S3-compatible storage) to be set in order to work.|
|DB_AUTO_BACKUP|Automatically backup database at given interval, possible values: `15min`, `hourly`, `daily`, `weekly`, `monthly`. If `AWS_BACKUP_ARN` configured, would also upload the file at `${AWS_RESOURCES_ARN}db.sql` location. |
|XDEBUG_CONFIG|Pass xdebug config string, e.g. `idekey=PHPSTORM remote_enable=1`. If no config provided the Xdebug extension will be disabled (safe for production), off by default|
|IMPORT_GITHUB_PUB_KEYS|Will pull authorized keys allowed to connect to this image from your Github account(s).|
|DB_DATABASE|Database name, defaults to `db`|
|DB_HOST|Database host, defaults to `db`|
|DB_PASS|Database password, defaults to `pass`|
|DB_USER|Database user, defaults to `admin`|


In addition to these settings, if you place database sql dump at `Data/Persistent/db.sql`, it would automatically be imported on the first container launch. See above for options to automatically download the data from AWS S3.
If `beard.json` file is present, your distribution will get [bearded](https://github.com/mneuhaus/Beard).

The container has the `crond` daemon running, put your scripts to `/etc/periodic` or `crontab -e`.

Example docker-compose.yml configuration:

```
web:
  image: dimaip/docker-neos-alpine:latest
  ports:
    - '80'
    - '22'
  links:
    - db:db
  volumes:
    - /data
  environment:
    REPOSITORY_URL: 'https://github.com/neos/neos-development-distribution'
    SITE_PACKAGE: 'Neos.Demo'
    VERSION: '3.3'
    ADMIN_PASSWORD: 'password'
    IMPORT_GITHUB_PUB_KEYS: 'your-github-user-name'
    AWS_RESOURCES_ARN: 's3://some-bucket/sites/demo/'
db:
  image: mariadb:latest
  expose:
    - 3306
  volumes:
    - /var/lib/data
  environment:
    MYSQL_DATABASE: 'db'
    MYSQL_USER: 'admin'
    MYSQL_PASSWORD: 'pass'
    MYSQL_RANDOM_ROOT_PASSWORD: 'yes'
```

## Utility scripts

Also this container provides a couple of utility scripts, they are located in the `/data` folder.

| Script name | Description |
|---------|-------------|
|backupDb.sh|Dumps database into `/data/www/Data/Persistent/db.sql` and uploads it to AWS S3, if it is set up.|
|syncDb.sh|Imports `/data/www/Data/Persistent/db.sql`, and dowloads it from AWS S3 beforehand, if it is set up.|
|syncCode.sh|For development purpose only! pulls latest code from git, does composer install and a few other things, see code.|
|syncAll.sh|Runs both syncDb and syncCode|

## Backups

Each container automatically takes care of daily backing up itself by running the `/data/backupDb.sh` script, which dumps DB and optionally uploads it to AWS S3. So if you store persistent resources on AWS S3, you are good to go (you should probably additionally backup the contents of S3 to some offline storage, but that's a different story).


## Two-step provisioning

You may build pre-provisioned images dedicated for your project from such Dockerfile:

```
FROM dimaip/docker-neos-alpine:latest
ENV PHP_TIMEZONE=Europe/Moscow
ENV REPOSITORY_URL=https://github.com/sfi-ru/ErmDistr
RUN /provision-neos.sh
```

It will already pre-install your project by running `composer install`, so the remaining startup will take about 10s, instead of minutes.