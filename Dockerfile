ARG ARCH=
FROM ${ARCH}erseco/alpine-php-webserver:3.20

LABEL maintainer="Ernesto Serrano <info@ernesto.es>"

USER root
RUN apk add --no-cache composer patch php83-posix php83-xmlwriter php83-pecl-redis \
    php83-ldap php83-pecl-igbinary php83-exif php83-sqlite3 php83-pdo_sqlite \
    # Remove alpine cache
    && rm -rf /var/cache/apk/*

# add a quick-and-dirty hack  to fix https://github.com/erseco/alpine-moodle/issues/26
RUN apk add --no-cache gnu-libiconv=1.15-r3 --repository http://dl-cdn.alpinelinux.org/alpine/v3.13/community/ --allow-untrusted \
    # Remove alpine cache
    && rm -rf /var/cache/apk/*
ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

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

# Apply experimental SQLite patches (MDL-88218) from ateeducacion/moodle.
# Each Moodle release branch has a matching patch PR:
#   main / v5.2+  → PR #1 (targets main)
#   v5.1.x        → PR #2 (targets MOODLE_501_STABLE)
#   v5.0.x        → PR #3 (targets MOODLE_500_STABLE)
# Older versions do not have SQLite patches; sqlite3 mode will be unavailable.
RUN SQLITE_PATCH_URL="" && \
    case "$MOODLE_VERSION" in \
      main|v5.2*) SQLITE_PATCH_URL="https://github.com/ateeducacion/moodle/pull/1.diff" ;; \
      v5.1*)      SQLITE_PATCH_URL="https://github.com/ateeducacion/moodle/pull/2.diff" ;; \
      v5.0*)      SQLITE_PATCH_URL="https://github.com/ateeducacion/moodle/pull/3.diff" ;; \
    esac && \
    if [ -n "$SQLITE_PATCH_URL" ]; then \
      echo "Applying SQLite patches from: $SQLITE_PATCH_URL" && \
      curl -fsSL "$SQLITE_PATCH_URL" -o /tmp/sqlite.diff && \
      patch -d /var/www/html -p1 --forward < /tmp/sqlite.diff && \
      rm -f /tmp/sqlite.diff && \
      echo "SQLite patches applied successfully."; \
    else \
      echo "WARNING: No SQLite patches available for MOODLE_VERSION=$MOODLE_VERSION (sqlite3 mode will not work)"; \
    fi

USER root
COPY --chown=nobody rootfs/ /

USER nobody

ENV MOOSH_URL=https://github.com/tmuras/moosh/archive/master.tar.gz
RUN curl -L "$MOOSH_URL" | tar xz --strip-components=1 -C /opt/moosh/

RUN composer install --no-interaction --no-cache --working-dir=/opt/moosh
