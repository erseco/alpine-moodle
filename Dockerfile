ARG ARCH=
FROM ${ARCH}erseco/alpine-php-webserver:1.13.0

LABEL maintainer="Ernesto Serrano <info@ernesto.es>"

USER root
COPY --chown=nobody rootfs/ /

# crond needs root, so install dcron and cap package and set the capabilities
# on dcron binary https://github.com/inter169/systs/blob/master/alpine/crond/README.md
RUN apk add --no-cache dcron libcap php8-sodium php8-exif && \
    chown nobody:nobody /usr/sbin/crond && \
    setcap cap_setgid=ep /usr/sbin/crond

USER nobody

# Change MOODLE_XX_STABLE for new versions
ENV MOODLE_URL=https://github.com/moodle/moodle/archive/MOODLE_400_STABLE.tar.gz \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    SITE_URL=http://localhost \
    DB_TYPE=pgsql \
    DB_HOST=postgres \
    DB_PORT=5432 \
    DB_NAME=moodle \
    DB_USER=moodle \
    DB_PASS=moodle \
    DB_PREFIX=mdl_ \
    SSLPROXY=false \
    MOODLE_EMAIL=user@example.com \
    MOODLE_LANGUAGE=en \
    MOODLE_SITENAME=New-Site \
    MOODLE_USERNAME=moodleuser \
    MOODLE_PASSWORD=PLEASE_CHANGEME \
    SMTP_HOST=smtp.gmail.com \
    SMTP_PORT=587 \
    SMTP_USER=your_email@gmail.com \
    SMTP_PASSWORD=your_password \
    SMTP_PROTOCOL=tls \
    MOODLE_MAIL_NOREPLY_ADDRESS=noreply@localhost \
    MOODLE_MAIL_PREFIX=[moodle] \
    client_max_body_size=50M \
    post_max_size=50M \
    upload_max_filesize=50M \
    max_input_vars=5000

RUN curl --location $MOODLE_URL | tar xz --strip-components=1 -C /var/www/html/

