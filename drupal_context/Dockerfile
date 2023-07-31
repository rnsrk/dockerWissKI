FROM php:8.2-apache-bullseye

# Install all the stuff we need
# Enable rewrite
RUN set -eux; \
	if command -v a2enmod; then \
		a2enmod rewrite; \
	fi

# Install packages 
RUN	apt-get update; \
	apt-get install -y --no-install-recommends \
		apt-utils \
		autoconf \
		automake \
		openjdk-11-jdk \
		git \
		iipimage-server \
		iipimage-doc \
		libapache2-mod-fcgid \
		libfreetype6-dev \
		libjpeg-dev \
		libjpeg62-turbo \
		libonig-dev \
		libpng-dev \
		libpng16-16 \
		libpq-dev \
		libtiff-dev \
		libtiff5 \
		libtool \
		libvips-dev \
		libvips-tools \
		libzip-dev \
		imagemagick \
		unzip \
		vim \
		wget

# already loaded php extensions:
# - Core
# - ctype
# - curl
# - date
# - fileinfo
# - ftp
# - hash
# - iconv
# - json
# - libxml
# - mbstring
# - mysqlnd
# - openssl
# - pcre
# - PDO
# - pdo_sqlite
# - Phar
# - posix
# - readline
# - Reflection
# - session
# - SimpleXML
# - sodium
# - SPL
# - sqlite3
# - standard
# - tokenizer
# - uploadprogress
# - xml
# - xmlreader
# - xmlwriter
# - Zend OPcache
# - zlib



# Add php extensions
RUN	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg=/usr \
		--with-webp

RUN	docker-php-ext-install -j "$(nproc)" \
		dom \
		filter \
		gd \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		zip

# Upload progress
RUN	set -eux; \
	git clone https://github.com/php/pecl-php-uploadprogress/ /usr/src/php/ext/uploadprogress/; \
	docker-php-ext-configure uploadprogress; \
	docker-php-ext-install uploadprogress; \
	rm -rf /usr/src/php/ext/uploadprogress;

# Install apcu
RUN set -eux; \
	pecl install apcu; \
	pecl install xdebug \
    docker-php-ext-enable xdebug; 


# Add php configs
RUN { \
		echo 'extension=apcu.so'; \
		echo "apc.enable_cli=1"; \
		echo "apc.enable=1"; \
	} >> /usr/local/etc/php/php.ini;

# Install iipsrv
RUN set -eux; \
	git clone https://github.com/ruven/iipsrv.git; \
	cd iipsrv; \
	./autogen.sh; \
	./configure; \
	make; \
	mkdir /fcgi-bin; \
	cp src/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi

# Add IIPServer config
COPY iipsrv.conf /etc/apache2/mods-available/iipsrv.conf 

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=0'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini;

# set memory settings for WissKi
RUN { \
		echo 'max_execution_time = 1200'; \
		echo 'max_input_time = 600'; \
		echo 'max_input_nesting_level = 640'; \
		echo 'max_input_vars = 10000'; \
		echo 'memory_limit = 2048M'; \
		echo 'upload_max_filesize = 512M'; \
		echo 'max_file_uploads = 50'; \
		echo 'post_max_size = 512M'; \
	} > /usr/local/etc/php/conf.d/wisski-settings.ini;

# reset apt
#	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
#	rm -rf /var/lib/apt/lists/*
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/

# Add private files directory
RUN mkdir /var/www/private_files && chown -R www-data:www-data /var/www/private_files

# Add Drupal directory
RUN mkdir /opt/drupal

# Change workdir
WORKDIR /opt/drupal

# Copy entrypoint to image
COPY entrypoint.sh /entrypoint.sh

# Copy Drupal settings from context to image 
COPY settings.php /settings.php

# (Re)link html dir
RUN ln -sf /opt/drupal/web /var/www/html

# Define entrypoint
ENTRYPOINT /entrypoint.sh

# vim:set ft=dockerfile:
