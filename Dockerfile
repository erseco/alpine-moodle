ARG ARCH=
FROM ${ARCH}erseco/alpine-php-webserver:latest

LABEL maintainer="Ernesto Serrano <info@ernesto.es>"

USER root
COPY --chown=nobody rootfs/ /

# crond needs root, so install dcron and cap package and set the capabilities
# on dcron binary https://github.com/inter169/systs/blob/master/alpine/crond/README.md
RUN apk add --no-cache dcron libcap php84-exif php84-pecl-redis php84-pecl-igbinary php84-ldap && \
    chown nobody:nobody /usr/sbin/crond && \
    setcap cap_setgid=ep /usr/sbin/crond

# add a quick-and-dirty hack  to fix https://github.com/erseco/alpine-moodle/issues/26
RUN apk add gnu-libiconv=1.15-r3 --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/v3.13/community/ --allow-untrusted
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so

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
