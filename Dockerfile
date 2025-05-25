ARG ARCH=
FROM ${ARCH}erseco/alpine-php-webserver:3.20.7

LABEL maintainer="Ernesto Serrano <info@ernesto.es>"

USER root
RUN apk add --no-cache composer php83-posix php83-xmlwriter php83-pecl-redis \
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
    DB_HOST=postgres \
    DB_PORT=5432 \
    DB_NAME=moodle \
    DB_USER=moodle \
    DB_PASS=moodle \
    DB_PREFIX=mdl_ \
    DB_DBHANDLEOPTIONS=false \
    REDIS_HOST= \
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
    max_input_vars=5000

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

USER root
COPY --chown=nobody rootfs/ /

USER nobody

ENV MOOSH_URL=https://github.com/tmuras/moosh/archive/refs/tags/1.27.tar.gz
RUN curl -L "$MOOSH_URL" | tar xz --strip-components=1 -C /opt/moosh/

RUN composer install --no-interaction --no-cache --working-dir=/opt/moosh
