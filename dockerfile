FROM php:8.1-apache as builder

LABEL vendor="NobinAlo"
LABEL maintainer="Tanjim Hossain <tanjimhossain.pro@gmail.com>"

# Install PHP extensions
RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates \
    build-essential  \
    git \
    curl \
    libcurl4-gnutls-dev \
    libc-client-dev \
    libkrb5-dev \
    libmcrypt-dev \
    libssl-dev \
    libxml2-dev \
    libzip-dev \
    libjpeg-dev \
    libmagickwand-dev \
    libpng-dev \
    libgif-dev \
    libtiff-dev \
    libz-dev \
    libpq-dev \
    imagemagick \
    graphicsmagick \
    libwebp-dev \
    libjpeg62-turbo-dev \
    libxpm-dev \
    libaprutil1-dev \
    libicu-dev \
    libfreetype6-dev \
    libonig-dev \
    librabbitmq-dev \
    unzip \
    nodejs \
    npm

# Enable PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-configure opcache --enable-opcache \
    && docker-php-ext-install intl mbstring mysqli curl pdo_mysql zip bcmath sockets exif gd imap opcache \
    && docker-php-ext-enable intl mbstring mysqli curl pdo_mysql zip bcmath sockets exif gd imap opcache

RUN echo "memory_limit = -1" > /usr/local/etc/php/php.ini

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

# Define Mautic version by package tag
ARG MAUTIC_VERSION=5

RUN cd /opt && \
    COMPOSER_PROCESS_TIMEOUT=10000 composer create-project mautic/recommended-project:${MAUTIC_VERSION} mautic --no-interaction && \
    rm -rf /opt/mautic/var/cache/js && \
    find /opt/mautic/node_modules -mindepth 1 -maxdepth 1 -not \( -name 'jquery' -or -name 'vimeo-froogaloop2' \) | xargs rm -rf

FROM php:8.1-apache

COPY --from=builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

COPY --from=builder --chown=www-data:www-data /opt/mautic /var/www/html

# Install PHP extensions requirements and other dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
    parallel unzip libwebp-dev libzip-dev libfreetype6-dev libjpeg62-turbo-dev libpng-dev libc-client-dev librabbitmq4 \
    mariadb-client cron \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/cron.daily/*

# Setting PHP properties
ENV PHP_INI_VALUE_DATE_TIMEZONE='UTC' \
    PHP_INI_VALUE_MEMORY_LIMIT=2048M \
    PHP_INI_VALUE_UPLOAD_MAX_FILESIZE=512M \
    PHP_INI_VALUE_POST_MAX_FILESIZE=512M \
    PHP_INI_VALUE_MAX_EXECUTION_TIME=1000

COPY ./php.ini /usr/local/etc/php/php.ini

ENV APACHE_DOCUMENT_ROOT=/var/www/html/docroot

RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Enable Apache Rewrite Module
RUN a2enmod rewrite

# Copy entrypoint script
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Define Mautic volumes to persist data
VOLUME /var/www/html/config
VOLUME /var/www/html/var/logs
VOLUME /var/www/html/docroot/media

WORKDIR /var/www/html/docroot

CMD ["/entrypoint.sh"]