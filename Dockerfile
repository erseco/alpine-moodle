ARG ARCH=
# Requires erseco/alpine-php-webserver 3.20.x with
# https://github.com/erseco/alpine-php-webserver/pull/92 (PHP iconv linked to
# modern GNU libiconv). That enables //TRANSLIT//IGNORE on Alpine/musl and
# replaces the previous LD_PRELOAD + gnu-libiconv 1.15-r3 workaround for
# https://github.com/erseco/alpine-moodle/issues/26.
# Pin major.minor so we track the latest 3.20.x patch (3.20.11+, e.g. 3.20.12).
ARG PHP_WEBSERVER_VERSION=3.20
FROM ${ARCH}erseco/alpine-php-webserver:${PHP_WEBSERVER_VERSION}

LABEL maintainer="Ernesto Serrano <info@ernesto.es>"

USER root
RUN apk add --no-cache composer patch php83-posix php83-xmlwriter php83-pecl-redis \
    php83-ldap php83-pecl-igbinary php83-exif php83-sqlite3 php83-pdo_sqlite \
    # php83-zip provides ZipArchive, used by the Moodle blueprint runner for
    # safe bundle/plugin extraction.
    php83-zip \
    # Remove alpine cache
    && rm -rf /var/cache/apk/*

USER nobody

# Moodle version configuration
ARG MOODLE_VERSION=main

# Set default environment variables
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    SITE_URL=http://localhost \
    DB_TYPE=pgsql \
    MOODLE_DATABASE_TYPE= \
    DB_HOST=postgres \
    DB_PORT=5432 \
    DB_NAME=moodle \
    DB_USER=moodle \
    DB_PASS=moodle \
    DB_PREFIX=mdl_ \
    DB_SQLITE_PATH=/var/www/moodledata/sqlite/moodle.sqlite \
    DB_DBHANDLEOPTIONS=false \
    REDIS_HOST= \
    REDIS_PASSWORD= \
    REDIS_USER= \
    REVERSEPROXY=false \
    SSLPROXY=false \
    MY_CERTIFICATES=none \
    MOODLE_EMAIL=user@example.com \
    MOODLE_LANGUAGE=en \
    MOODLE_SITENAME=Dockerized_Moodle \
    MOODLE_USERNAME=moodleuser \
    MOODLE_PASSWORD=PLEASE_CHANGEME \
    SMTP_HOST=smtp.gmail.com \
    SMTP_PORT=587 \
    SMTP_USER=your_email@gmail.com \
    SMTP_PASSWORD=your_password \
    SMTP_PROTOCOL=tls \
    MOODLE_MAIL_NOREPLY_ADDRESS=noreply@localhost \
    MOODLE_MAIL_PREFIX=[moodle] \
    AUTO_UPDATE_MOODLE=true \
    DEBUG=false \
    client_max_body_size=50M \
    post_max_size=50M \
    upload_max_filesize=50M \
    max_input_vars=5000 \
    memory_limit=256M

# To use a specific Moodle version, set MOODLE_VERSION to git release tag.
# You can find the list of available tags at:
# https://api.github.com/repos/moodle/moodle/tags
#
# Example:
# MOODLE_VERSION=v4.5.3
#
# Download and extract Moodle
RUN if [ "$MOODLE_VERSION" = "main" ]; then \
      MOODLE_URL="https://github.com/moodle/moodle/archive/main.tar.gz"; \
    else \
      MOODLE_URL="https://github.com/moodle/moodle/tarball/refs/tags/${MOODLE_VERSION}"; \
    fi && \
    echo "Downloading Moodle from: $MOODLE_URL" && \
    curl -L "$MOODLE_URL" | tar xz --strip-components=1 -C /var/www/html/

# Apply experimental SQLite support (MDL-88218). The heavy lifting — selecting
# the right ateeducacion/moodle patch per branch (PR #1 main, #5 5.2, #2 5.1,
# #3 5.0, #4 4.5), tolerating cosmetic hunk rejects, verifying the SQLite driver is
# present, and declaring the sqlite VENDOR in the installed version's
# environment.xml block — lives in scripts/apply-sqlite-support.sh (see its
# header for the full rationale). Versions without a patch keep SQLite disabled.
# Runs as nobody (like the Moodle download above) so the tree stays nobody-owned.
COPY --chown=nobody scripts/apply-sqlite-support.sh /tmp/apply-sqlite-support.sh
RUN sh /tmp/apply-sqlite-support.sh "$MOODLE_VERSION" && rm -f /tmp/apply-sqlite-support.sh

USER root
COPY --chown=nobody rootfs/ /

USER nobody

ENV MOOSH_URL=https://github.com/tmuras/moosh/archive/master.tar.gz
RUN curl -L "$MOOSH_URL" | tar xz --strip-components=1 -C /opt/moosh/

RUN composer install --no-interaction --no-cache --working-dir=/opt/moosh
