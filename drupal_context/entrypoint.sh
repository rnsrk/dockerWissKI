#!/bin/bash

# Entrypoint to install Drupal in container

# Check if installation already exists
if ! [ -d /opt/drupal/web ]
	then
		# https://www.drupal.org/node/3060/release
		DRUPAL_VERSION='10.0.8'

		# Installed Drupal modules, please check and update versions if necessary
		# List Requirements
		REQUIREMENTS="drupal/colorbox \
			drupal/devel \
			drush/drush \
			drupal/facets \
			drupal/field_permissions \
			drupal/geofield \
			drupal/geofield_map \
			drupal/image_effects \
			drupal/imagemagick \
			drupal/imce \
			drupal/inline_entity_form:^1.0@RC \
			kint-php/kint \
			drupal/leaflet \
			drupal/search_api \
			drupal/search_api_solr \
			drupal/viewfield:^3.0@beta \
			drupal/wisski:3.x-dev@dev"

		# Install Drupal, WissKI and dependencies
		set -eux
		export COMPOSER_HOME="$(mktemp -d)"
		composer create-project --no-interaction "drupal/recommended-project:$DRUPAL_VERSION" ./
		yes | composer require ${REQUIREMENTS}

		# delete composer cache
		rm -rf "$COMPOSER_HOME"

		# install libraries
		set -eux
		mkdir -p web/libraries
		wget https://github.com/jackmoore/colorbox/archive/refs/heads/master.zip -P web/libraries/
		unzip web/libraries/master.zip -d web/libraries/
		rm -r web/libraries/master.zip
		mv web/libraries/colorbox-master web/libraries/colorbox

		# IIPMooViewer
		wget https://github.com/ruven/iipmooviewer/archive/refs/heads/master.zip -P web/libraries/
		unzip web/libraries/master.zip -d web/libraries/
		rm -r web/libraries/master.zip
		mv web/libraries/iipmooviewer-master web/libraries/iipmooviewer

		# Mirador
		wget https://github.com/rnsrk/wisski-mirador-integration/archive/refs/heads/main.zip -P web/libraries/
		unzip web/libraries/main.zip -d web/libraries/
		mv web/libraries/wisski-mirador-integration-main web/libraries/wisski-mirador-integration

		# Replace databse settings
		drush php:eval "
			\$settings = file_get_contents('sites/default/settings.php');
			\$db_options = <<<EOT
			\$databases['default']['default'] = array (
  			'database' => getenv('DB_NAME'),
  			'username' => getenv('DB_USER'),
  			'password' => getenv('DB_PASSWORD'),
  			'host' => getenv('DB_HOST'),
  			'driver' => getenv('DB_DRIVER'),
			);
			EOT;
			\$settings = preg_replace(\"/(\\\$databases\\['default'\\]\\['default'\\] = array \\(.*?\\);)/s\", \$db_options, \$settings);
			file_put_contents('sites/default/settings.php', \$settings);
		"
		

		# Set permissions
		chmod -R 644 web/sites/default/settings.php
		chown -R www-data:www-data /opt/drupal
	else
		echo "/opt/drupal/web already exists."
fi

# Adjust permissions and links
	rm -r /var/www/html
	ln -sf /opt/drupal/web /var/www/html

# Show apache log and keep server running
/usr/sbin/apache2ctl -D FOREGROUND