ARG INPUT_PHP="8.3"
ARG IMAGENAME=dunglas/frankenphp:php${INPUT_PHP}-alpine

FROM $IMAGENAME

ARG TARGETARCH
ARG INSTALL_CHROMIUM=false

############################################################
###############  GENERAL DEPENDENCIES ######################
############################################################

# Create non-root user with UID 1000 to match host user
RUN addgroup -g 1000 laravel \
 && adduser -D -u 1000 -G laravel -s /bin/sh laravel \
 && addgroup laravel www-data

# Install dependencies including Nginx, Supervisor, Cron, and security tools
RUN apk update && apk add --no-cache \
    bash \
    curl \
    git \
    zip \
    imagemagick \
    mysql-client \
    postgresql-client \
    nano \
    nodejs \
    npm \
    nginx \
    supervisor \
    ca-certificates \
    tzdata \
    jq \
    openssl

# Install puppeteer PDF tools dependencies (optional, controlled by INSTALL_CHROMIUM build arg)
RUN if [ "$INSTALL_CHROMIUM" = "true" ]; then \
      apk update && apk add --no-cache \
         chromium \
         nss \
         freetype \
         harfbuzz \
         ttf-freefont \
         libc6-compat \
         gcompat; \
    fi

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# PHP Extension installer
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install PHP Extensions (grouped in one layer for optimization)
RUN install-php-extensions @composer \
    gd bcmath bz2 calendar iconv intl mbstring \
    mysqli pdo_mysql pdo_pgsql soap zip gmp ldap \
    exif memcached redis imap pcntl openssl tokenizer \
    xml ctype json imagick sockets opcache xdebug

# Configure Nginx
COPY ./src/shared/nginx/nginx.base.conf /etc/nginx/nginx.conf
COPY ./src/shared/nginx/nginx.octane.conf /etc/nginx/http.d/default.conf
COPY ./src/shared/nginx/maintenance /etc/nginx/maintenance
RUN mkdir -p /var/run/nginx /var/lib/nginx/tmp /etc/nginx/ssl && \
    touch /etc/nginx/php-fpm-handler.conf /etc/nginx/php-restriction.conf && \
    chown -R laravel:laravel /var/lib/nginx /var/run/nginx /var/log/nginx /etc/nginx/ssl \
        /etc/nginx/php-fpm-handler.conf /etc/nginx/php-restriction.conf

# Configure Supervisor. Add your Supervisor configuration files here.
COPY ./src/shared/supervisor/ /tmp/supervisor/
RUN mkdir -p /etc/supervisor/conf.d/ && cp -n /tmp/supervisor/* /etc/supervisor/conf.d/ && rm -r /tmp/supervisor/

# Download and install Supercronic
RUN curl -sSL -o /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/latest/download/supercronic-linux-${TARGETARCH} \
 && chmod +x /usr/local/bin/supercronic
# Configure Cron Jobs (if needed). You can add cron jobs by creating a crontab file and mounting it into the container.
COPY ./src/shared/laravel-cron /etc/supercronic.txt
RUN chown 1000:1000 /etc/supercronic.txt

# Copy custom php.ini configuration
COPY ./src/shared/php.ini /usr/local/etc/php/

# Yes, different path for xdebug config, disabled by default
COPY ./src/shared/xdebug.ini /usr/local/etc/php/conf.d/xdebug.ini.disabled
# Remove xdebug ini file from extension installer
RUN rm /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Set up the application working directory
WORKDIR /app

# Copy entire scripts folder into container
COPY ./src/shared/scripts /scripts

# Make all *.sh files in /scripts executable
RUN find /scripts -type f -name "*.sh" -exec chmod +x {} \;

# Set secure ownership and permissions for Supervisor config directory
RUN chown -R laravel:laravel /etc/supervisor/conf.d \
 && chmod -R 755 /etc/supervisor/conf.d

# Pre-create PHP security hardening file writable by laravel (directory stays root-owned)
RUN touch /usr/local/etc/php/conf.d/security-hardening.ini \
 && chown laravel:laravel /usr/local/etc/php/conf.d/security-hardening.ini

# Set the user to run the container
USER laravel

# Expose the ports Nginx is reachable on
EXPOSE 8000 8443

# Set Bash as the default shell
SHELL ["/bin/bash", "-c"]

ENV PHP_RUNTIME_CONFIG=frankenphp
ENV PHP_IDE_CONFIG="serverName=laravel"

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -sf http://localhost:8000/basic_status || exit 1

# Define the command to run on container start
ENTRYPOINT ["/scripts/entrypoint.sh"]
