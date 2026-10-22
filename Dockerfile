# Requires erseco/alpine-php-webserver 3.23.x or later with
# https://github.com/erseco/alpine-php-webserver/pull/89 (PHP iconv linked to
# modern GNU libiconv). That enables //TRANSLIT//IGNORE on Alpine/musl and
# replaces the previous LD_PRELOAD + gnu-libiconv 1.15-r3 workaround for
# https://github.com/erseco/alpine-moodle/issues/26.
# Release CI selects 3.24-php83 (PHP 8.3) for Moodle 4.5–5.2 and 3.24-php84
# (PHP 8.4) for 5.3 and later, both on Alpine 3.24. Moodle 4.1 uses the php81
# stage below (PHP_BASE=php81, see scripts/image-runtime.sh).
ARG PHP_WEBSERVER_VERSION=3.24-php84
# webserver: the prebuilt alpine-php-webserver image as is.
# php81: that image with its PHP swapped for PHP 8.1 compiled from source.
ARG PHP_BASE=webserver
FROM ghcr.io/erseco/alpine-php-webserver:${PHP_WEBSERVER_VERSION} AS webserver

# PHP 8.1 for Moodle 4.1, which refuses PHP >= 8.2 (#189). PHP 8.1 is EOL and
# Alpine no longer packages it, but php-src published a source-only backport
# of the CVE-2026-109618/CVE-2026-109619 fixes on the
# PHP-8.1-CVE-2026-109618-109619 branch; PHP81_COMMIT pins that commit.
FROM alpine:3.24 AS php81-build
ARG PHP81_COMMIT=1d7dec178a094e6e75b229ce22754045f8c6070a
ARG PHP81_EXTRA_VERSION=-cve-2026-109618-109619
ARG IGBINARY_VERSION=3.2.16
ARG REDIS_VERSION=6.2.0
ARG APCU_VERSION=5.1.24
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# hadolint ignore=DL3018
RUN apk add --no-cache autoconf bison build-base curl curl-dev freetype-dev \
        gnu-libiconv-dev icu-dev libjpeg-turbo-dev libpng-dev libpq-dev \
        libsodium-dev libwebp-dev libxml2-dev libzip-dev linux-headers \
        oniguruma-dev openldap-dev openssl-dev pax-utils pkgconf re2c sqlite-dev zlib-dev \
    # Build iconv against GNU libiconv for //TRANSLIT//IGNORE (#26), like the
    # alpine-php-webserver images do.
    && cp /usr/include/gnu-libiconv/iconv.h /usr/include/iconv.h \
    && mkdir -p /usr/src/php \
    && curl -fsSL --retry 5 "https://github.com/php/php-src/archive/${PHP81_COMMIT}.tar.gz" \
       | tar xz --strip-components=1 -C /usr/src/php
WORKDIR /usr/src/php
# GCC 14 turned these warnings into errors; PHP 8.1 predates that. ICU 74+
# headers need C++17. Same --program-suffix and paths as Alpine's php81 so the
# webserver scripts (php-fpm${PHP_SUFFIX}, /etc/php${PHP_SUFFIX}) work as is.
RUN ./buildconf --force \
    && EXTENSION_DIR=/usr/lib/php81/modules \
       CFLAGS="-O2 -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=implicit-function-declaration" \
       CXXFLAGS="-O2 -std=c++17" LIBS="-liconv" \
       ./configure --prefix=/usr --program-suffix=81 --sysconfdir=/etc/php81 \
        --with-config-file-path=/etc/php81 --with-config-file-scan-dir=/etc/php81/conf.d \
        --disable-cgi --enable-fpm --with-fpm-user=nobody --with-fpm-group=nobody \
        --enable-bcmath --enable-exif --enable-gd --enable-intl --enable-mbstring \
        --enable-opcache --enable-soap --enable-sockets --with-curl --with-freetype \
        --with-iconv=/usr --with-jpeg --with-ldap --with-mysqli --with-openssl \
        --with-pdo-mysql --with-pdo-pgsql --with-pdo-sqlite --with-pgsql --with-sodium \
        --with-sqlite3 --with-webp --with-zip --with-zlib \
    # Make the patched build identifiable in php -v / phpversion().
    && sed -i "s/^#define PHP_EXTRA_VERSION \"\"/#define PHP_EXTRA_VERSION \"${PHP81_EXTRA_VERSION}\"/; s/^#define PHP_VERSION \"\\([0-9.]*\\)\"/#define PHP_VERSION \"\\1${PHP81_EXTRA_VERSION}\"/" main/php_version.h \
    && grep -q "${PHP81_EXTRA_VERSION}" main/php_version.h \
    && make -j"$(nproc)" \
    && make install \
    && install -D -m644 php.ini-production /etc/php81/php.ini
# PECL extensions Moodle uses (Alpine ships them as php83-pecl-* packages).
WORKDIR /usr/src
# hadolint ignore=DL3003
RUN for ext in "igbinary-${IGBINARY_VERSION}" "redis-${REDIS_VERSION}" "apcu-${APCU_VERSION}"; do \
      curl -fsSL --retry 5 "https://pecl.php.net/get/${ext}.tgz" | tar xz; \
      ( cd "$ext" && phpize81 \
        && if [ "${ext%%-*}" = redis ]; then ./configure --with-php-config=php-config81 --enable-redis-igbinary; \
           else ./configure --with-php-config=php-config81; fi \
        && make -j"$(nproc)" && make install ); \
    done \
    && mkdir -p /etc/php81/conf.d \
    && echo 'zend_extension=opcache' > /etc/php81/conf.d/00_opcache.ini \
    && echo 'extension=igbinary' > /etc/php81/conf.d/10_igbinary.ini \
    && echo 'extension=redis' > /etc/php81/conf.d/20_redis.ini \
    && echo 'extension=apcu' > /etc/php81/conf.d/apcu.ini \
    && printf '[global]\ninclude=/etc/php81/php-fpm.d/*.conf\n' > /etc/php81/php-fpm.conf \
    # Shared libraries the runtime stage must install, as apk so: names.
    && scanelf --needed --nobanner --format '%n#p' --recursive /usr/bin/php81 /usr/sbin/php-fpm81 /usr/lib/php81/modules \
       | tr ',' '\n' | sort -u | sed 's/^/so:/' > /etc/php81/.runtime-deps

FROM webserver AS php81
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
USER root
COPY --from=php81-build /usr/bin/php81 /usr/bin/php81
COPY --from=php81-build /usr/sbin/php-fpm81 /usr/sbin/php-fpm81
COPY --from=php81-build /usr/lib/php81/ /usr/lib/php81/
COPY --from=php81-build /etc/php81/ /etc/php81/
# Swap the base image's PHP (PHP_SUFFIX, 83 on 3.24-php83) for the compiled
# PHP 8.1, keeping its nginx, runit services, entrypoint and the PHP config
# templates it renders at start.
# hadolint ignore=DL3018,SC2046
RUN cp "/etc/php${PHP_SUFFIX}/conf.d/custom.ini.tpl" /etc/php81/conf.d/custom.ini.tpl \
    && mkdir -p /etc/php81/php-fpm.d \
    && cp "/etc/php${PHP_SUFFIX}/php-fpm.d/www.conf" /etc/php81/php-fpm.d/www.conf \
    && apk del --no-cache $(apk info | grep "^php${PHP_SUFFIX}") \
    && rm -rf "/etc/php${PHP_SUFFIX}" "/usr/lib/php${PHP_SUFFIX}" \
    && apk add --no-cache $(cat /etc/php81/.runtime-deps) \
    && rm -f /etc/php81/.runtime-deps \
    && ln -sf php81 /usr/bin/php \
    && chown -R nobody:nobody /etc/php81 \
    && php -v \
    && out="$(php -r 'echo iconv("UTF-8", "ASCII//TRANSLIT//IGNORE", "café");')" \
    && echo "iconv TRANSLIT check: $out" && [ -n "$out" ] \
    && [ "$(php -r 'echo ICONV_IMPL;')" = libiconv ]
ENV PHP_SUFFIX=81
USER nobody

# hadolint ignore=DL3006
FROM ${PHP_BASE}

LABEL maintainer="Ernesto Serrano <info@ernesto.es>"

USER root
# Composer comes from the official image: on the 3.24-php83 base, Alpine's
# composer package depends on php85 and would repoint /usr/bin/php.
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ARG PHP_VERSION=84
# The php81 base compiles these extensions in already.
# hadolint ignore=SC2086
RUN case "$PHP_VERSION" in \
      81) php_packages= ;; \
      83|84) php_packages="php${PHP_VERSION}-posix php${PHP_VERSION}-xmlwriter php${PHP_VERSION}-pecl-redis \
        php${PHP_VERSION}-ldap php${PHP_VERSION}-pecl-igbinary php${PHP_VERSION}-exif php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-pdo_sqlite php${PHP_VERSION}-zip" ;; \
      *) echo 'Unsupported PHP runtime' >&2; exit 1 ;; \
    esac \
    # php*-zip provides ZipArchive, used by the Moodle blueprint runner for
    # safe bundle/plugin extraction.
    && apk add --no-cache patch rsync $php_packages \
    && test "$(php -r 'echo PHP_MAJOR_VERSION, PHP_MINOR_VERSION;')" = "$PHP_VERSION" \
    # Remove alpine cache
    && rm -rf /var/cache/apk/* \
    # Immutable Moodle source tree used by 010-sync-moodle-code.sh to refresh
    # /var/www/html when a named volume holds an older release (#103).
    && mkdir -p /usr/src/moodle \
    && chown nobody:nobody /usr/src/moodle

USER nobody

# Moodle version configuration
ARG MOODLE_VERSION=main
RUN case "$MOODLE_VERSION:$PHP_VERSION" in \
      v4.1.*:81) ;; \
      v4.1.*:*) echo 'Moodle 4.1 requires PHP 8.1' >&2; exit 1 ;; \
      v4.*:84) echo 'Moodle 4.x does not support PHP 8.4' >&2; exit 1 ;; \
    esac
# Exact moodle/moodle commit for the download below. CI (build.yml) resolves
# it from MOODLE_VERSION with git ls-remote, so the download layer's cache key
# changes whenever upstream moves — without it, BuildKit reused a months-old
# cached "main" snapshot in every :main/:beta image (#161). Optional for local
# builds: when empty, the ref name is downloaded directly.
ARG MOODLE_COMMIT=

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
    # auto: rsync /usr/src/moodle → /var/www/html when the volume's Moodle
    # $version differs from the image (or the tree is empty). always/never
    # override. See docs/upgrading.md and #103.
    SYNC_MOODLE_CODE=auto \
    # true: the code sync keeps third-party plugins (any directory with a
    # version.php that the image tree does not ship) instead of deleting
    # them, matching Moodle's own upgrade procedure. See #161.
    SYNC_PRESERVE_PLUGINS=true \
    EXTRA_PLUGIN_PATHS= \
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
# MOODLE_COMMIT (optional) pins the exact commit to download; when set it
# takes precedence over MOODLE_VERSION for the URL.
#
# Download and extract Moodle into the immutable source tree, then seed the
# runtime document root. Runtime upgrades of a persistent moodlehtml volume are
# handled by rootfs/docker-entrypoint-init.d/010-sync-moodle-code.sh.
RUN if [ -n "$MOODLE_COMMIT" ]; then \
      MOODLE_URL="https://github.com/moodle/moodle/archive/${MOODLE_COMMIT}.tar.gz"; \
    elif [ "$MOODLE_VERSION" = "main" ]; then \
      MOODLE_URL="https://github.com/moodle/moodle/archive/refs/heads/main.tar.gz"; \
    else \
      MOODLE_URL="https://github.com/moodle/moodle/archive/refs/tags/${MOODLE_VERSION}.tar.gz"; \
    fi && \
    echo "Downloading Moodle ${MOODLE_VERSION}${MOODLE_COMMIT:+ (commit ${MOODLE_COMMIT})} from: $MOODLE_URL" && \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 "$MOODLE_URL" -o /tmp/moodle.tar.gz && \
    tar xzf /tmp/moodle.tar.gz --strip-components=1 -C /usr/src/moodle && \
    rm -f /tmp/moodle.tar.gz

# Apply experimental SQLite support (MDL-88218). The heavy lifting — selecting
# the right ateeducacion/moodle patch per branch (PR #1 main, #5 5.2, #2 5.1,
# #3 5.0, #4 4.5), tolerating cosmetic hunk rejects, verifying the SQLite driver is
# present, and declaring the sqlite VENDOR in the installed version's
# environment.xml block — lives in scripts/apply-sqlite-support.sh (see its
# header for the full rationale). Versions without a patch keep SQLite disabled.
# Runs as nobody (like the Moodle download above) so the tree stays nobody-owned.
COPY --chown=nobody scripts/apply-sqlite-support.sh /tmp/apply-sqlite-support.sh
RUN MOODLE_DIR=/usr/src/moodle sh /tmp/apply-sqlite-support.sh "$MOODLE_VERSION" \
    && rm -f /tmp/apply-sqlite-support.sh \
    # Seed the runtime tree and write the release stamp used by the sync script.
    # Moodle <5.1 keeps version.php at the tree root; 5.1+ moved it under public/.
    && cp -a /usr/src/moodle/. /var/www/html/ \
    && VERSION_PHP=/usr/src/moodle/version.php \
    && if [ ! -f "$VERSION_PHP" ]; then VERSION_PHP=/usr/src/moodle/public/version.php; fi \
    && sed -n 's/^[[:space:]]*\$version[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
         "$VERSION_PHP" | head -n 1 \
         > /var/www/html/.alpine-moodle-release \
    && cp /var/www/html/.alpine-moodle-release /usr/src/moodle/.alpine-moodle-release

USER root
COPY --chown=nobody rootfs/ /

USER nobody

ENV MOOSH_URL=https://github.com/tmuras/moosh/archive/master.tar.gz
RUN curl -L "$MOOSH_URL" | tar xz --strip-components=1 -C /opt/moosh/

RUN composer install --no-interaction --no-cache --working-dir=/opt/moosh
