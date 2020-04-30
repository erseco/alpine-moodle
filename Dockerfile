FROM erseco/alpine-php7-webserver

MAINTAINER Ernesto Serrano <info@ernesto.es>

USER root
COPY config/cronjob /etc/crontabs/nobody
USER nobody

COPY --chown=nobody config/cron.run /etc/service/cron/run

RUN mkdir /var/www/moodledata/

# ENV MOODLE_VERSION=v3.8.2
ENV MOODLE_VERSION=MOODLE_38_STABLE
ENV MOODLE_URL=https://github.com/moodle/moodle/archive/$MOODLE_VERSION.tar.gz

RUN curl --location $MOODLE_URL | tar xz --strip-components=1 -C /var/www/html/

COPY config/configure-moodle.sh /docker-entrypoint-init.d/configure-moodle.sh

COPY config/isinstalled.php /var/www/html/admin/cli/isinstalled.php

ENV LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    SITE_URL="http://localhost" \
    DB_TYPE="pgsql" \
    DB_HOST="postgres" \
    DB_PORT="5432" \
    DB_NAME="moodle" \
    DB_USER="moodle" \
    DB_PASS="moodle" \
    DB_PREFIX="mdl_" \
    DB_COLLATION="utf8mb4_unicode_ci" \
    MOODLE_EMAIL="user@example.com" \
    MOODLE_LANGUAGE="en" \
    MOODLE_SITENAME="New Site" \
    MOODLE_USERNAME="moodleuser" \
    MOODLE_PASSWORD="PLEASE_CHANGE_ME" \
    SMTP_HOST=smtp.gmail.com \
    SMTP_PORT=587 \
    SMTP_USER=your_email@gmail.com \
    SMTP_PASSWORD=your_password \
    SMTP_PROTOCOL=tls \
    MOODLE_MAIL_NOREPLY_ADDRESS="noreply@localhost" \
    MOODLE_MAIL_PREFIX="[moodle]"
