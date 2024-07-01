#!/bin/bash

# Entrypoint to install Drupal in container

# Check if installation already exists
if ! [ -d /opt/drupal/web ]
	then
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
		composer create-project --no-interaction "drupal/recommended-project:${DRUPAL_VERSION}" ./
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

		# Replace database settings
		cp web/sites/default/default.settings.php web/sites/default/settings.php
		printf "\$databases['default']['default'] = [
'database' => '%s',
'username' => '%s',
'password' => '%s',
'host' => '%s',
'driver' => '%s'
];\n" "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}" "${DB_HOST}" "${DB_DRIVER}" >> web/sites/default/settings.php

		# Set permissions
		chown -R www-data:www-data /opt/drupal

		# Make drush available in the whole container
		ln -s /opt/drupal/vendor/bin/drush /usr/local/bin

		printf 'Waiting for GraphDB to start'
		until curl --output /dev/null --silent --head --fail http://graphdb:7200/protocol; do
			printf '.'
			sleep 1
		done
		echo

		# Create the default repo in the Triplestore
		curl -X POST http://graphdb:7200/rest/repositories -H 'Content-Type: multipart/form-data' -F config=@/setup/create_repo.ttl
		echo

		# Install the site
		drush site:install \
			--db-url="${DB_HOST}" \
			--db-su="${DB_USER}" \
			--db-su-pw="${DB_PASSWORD}" \
			--site-name="${SITE_NAME}" \
			--account-name="${DRUPAL_USER}" \
			--account-pass="${DRUPAL_PASSWORD}" \

		# Enable WissKI by default
		drush en wisski

		# Create the default SALZ adapter
		drush php:script /setup/create_adapter.php

	else
		echo "/opt/drupal/web already exists. So nothing was installed."
fi

# Adjust permissions and links
	rm -r /var/www/html
	ln -sf /opt/drupal/web /var/www/html

# Show apache log and keep server running
/usr/sbin/apache2ctl -D FOREGROUND