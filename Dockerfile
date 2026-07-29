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
RUN apk add --no-cache composer patch rsync php83-posix php83-xmlwriter php83-pecl-redis \
    php83-ldap php83-pecl-igbinary php83-exif php83-sqlite3 php83-pdo_sqlite \
    # php83-zip provides ZipArchive, used by the Moodle blueprint runner for
    # safe bundle/plugin extraction.
    php83-zip \
    # Remove alpine cache
    && rm -rf /var/cache/apk/* \
    # Immutable Moodle source tree used by 010-sync-moodle-code.sh to refresh
    # /var/www/html when a named volume holds an older release (#103).
    && mkdir -p /usr/src/moodle \
    && chown nobody:nobody /usr/src/moodle

USER nobody

# Moodle version configuration
ARG MOODLE_VERSION=main
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
    curl -fsSL "$MOODLE_URL" -o /tmp/moodle.tar.gz && \
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
