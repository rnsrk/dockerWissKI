# Dockerfile for creating Drupal-instance with WissḰI-enviroment

# from https://www.drupal.org/docs/system-requirements/php-requirements
FROM php:7.4-apache-buster

# install the PHP extensions we need
RUN set -eux; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite; \
	fi;

# create javamandummy
RUN	mkdir -p /usr/share/man/man1;

# install build packages

RUN	apt-get update; \
	apt-get install -y \
		autoconf \
		automake \
		default-jdk \
		git \
		iipimage-server \
		iipimage-doc \
		libapache2-mod-fcgid \
		libfreetype6-dev \
		libjpeg-dev \
		libjpeg62-turbo \
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
		wget; 

RUN	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg=/usr;	

RUN	docker-php-ext-install -j "$(nproc)" \
		gd \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		zip;

RUN	git clone https://github.com/php/pecl-php-uploadprogress/ /usr/src/php/ext/uploadprogress/; \
	docker-php-ext-configure uploadprogress; \
	docker-php-ext-install uploadprogress; \
	rm -rf /usr/src/php/ext/uploadprogress; 

# install iipsrv
RUN git clone https://github.com/ruven/iipsrv.git && \
	cd iipsrv && \
	./autogen.sh && \
	./configure && \
	make && \
	cp src/iipsrv.fcgi /usr/lib/iipimage-server/iipsrv.fcgi;

#INSTALL APCU
RUN pecl install apcu;

RUN { \
		echo 'extension=apcu.so'; \
		echo "apc.enable_cli=1"; \
		echo "apc.enable=1"; \
	} >> /usr/local/etc/php/php.ini;

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# set memory settings for WissKi
RUN { \
		echo 'max_execution_time = 1200'; \
		echo 'max_input_time = 600'; \
		echo 'max_input_nesting_level = 640'; \
		echo 'max_input_vars = 10000'; \
		echo 'memory_limit = 512M'; \
		echo 'upload_max_filesize = 512M'; \
		echo 'max_file_uploads = 50'; \
		echo 'post_max_size = 512M'; \
	} > /usr/local/etc/php/conf.d/wisski-settings.ini

# copy composer to right place
COPY --from=composer:2.0 /usr/bin/composer /usr/local/bin/

# https://www.drupal.org/node/3060/release
ENV DRUPAL_VERSION 9.2.5

# Installed Drupal modules, please check and update versions if necessary
ENV REQUIREMENTS="drupal/colorbox \
	drupal/devel \
	drupal/facets \
	drupal/field_permissions \
	drupal/geofield \
	drupal/geofield_map \
	drupal/image_effects \
	drupal/imagemagick \
	drupal/imce \
	drupal/inline_entity_form:1.x-dev@dev \
	kint-php/kint \
	drupal/leaflet \
	drupal/search_api \
	drupal/search_api_solr \
	drupal/viewfield:3.x-dev@dev \
	drupal/wisski:^3.0@RC"

#change workdir
WORKDIR /opt/drupal

# install Drupal and requirements
RUN set -eux; \
	export COMPOSER_HOME="$(mktemp -d)"; \
	composer create-project --no-interaction "drupal/recommended-project:$DRUPAL_VERSION" ./; \
	composer require ${REQUIREMENTS}; \
	composer require --dev drush/drush; \
	cd web/modules/contrib/wisski && composer update && cd /opt/drupal; \
	mkdir -p web/sites/default/files/drupal_sync; \
	chown -R www-data:www-data web/sites web/modules web/themes; \
	rm -r /var/www/html; \
	ln -sf /opt/drupal/web /var/www/html; \
	# delete composer cache
	rm -rf "$COMPOSER_HOME"

# install libraries
RUN mkdir -p web/libraries; \
	wget https://github.com/jackmoore/colorbox/archive/refs/heads/master.zip -P web/libraries/; \
	unzip web/libraries/master.zip -d web/libraries/; \
	mv web/libraries/colorbox-master web/libraries/colorbox;

COPY iipmooviewer.zip web/libraries/

COPY mirador.zip web/libraries/

RUN unzip web/libraries/iipmooviewer.zip -d web/libraries/; \
	unzip web/libraries/mirador.zip -d web/libraries/; 

# remove apt ĺists
RUN	rm -rf /var/lib/apt/lists/*

# add vendor to PATH
ENV PATH=${PATH}:/opt/drupal/vendor/bin

# add iipserver config
COPY iipsrv.conf /etc/apache2/mods-available/iipsrv.conf 

# add private files directory
RUN mkdir /var/www/private_files && chown -R www-data /var/www/private_files

# vim:set ft=dockerfile:
