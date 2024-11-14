#!/bin/bash

# Entrypoint to install Drupal in container

# Check if installation already exists
if ! [ -d /opt/drupal/web ]
	then

		# Installed Drupal modules, please check and update versions if necessary
		# List Requirements
		REQUIREMENTS="drupal/colorbox:^2.1 \
			drupal/devel:^5.3 \
			drush/drush \
			drupal/facets:^2.0 \
			drupal/field_permissions:^1.4 \
			drupal/geofield:^1.62 \
			drupal/geofield_map:^11.0 \
			drupal/image_effects:^4.0@RC \
			drupal/imagemagick:^4.0 \
			drupal/imce:^3.1 \
			drupal/inline_entity_form:^3.0@RC \
			kint-php/kint \
			drupal/leaflet:^10.2 \
			drupal/search_api:^1.35 \
			drupal/search_api_solr:^4.3 \
			drupal/viewfield:^3.0@beta \
			drupal/wisski:3.x-dev@dev \
			ewcomposer/unpack:dev-master"

		# Install Drupal, WissKI and dependencies
		set -eux
		composer create-project --no-interaction "drupal/recommended-project:${DRUPAL_VERSION}" .

		# Lets get dirty with composer
		composer config minimum-stability dev

		  # Add Drupal Recipe Composer plugin
    composer config repositories.ewdev vcs https://gitlab.ewdev.ca/yonas.legesse/drupal-recipe-unpack.git
    composer config allow-plugins.ewcomposer/unpack true

		yes | composer require ${REQUIREMENTS}

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
		drush si --db-url="${DB_DRIVER}://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:3306/${DB_NAME}" --site-name="${SITE_NAME}" --account-name="${DRUPAL_USER}" --account-pass="${DRUPAL_PASSWORD}"

		# Enable WissKI by default
		drush en wisski

		# Create the default SALZ adapter
		drush php:script /setup/create_adapter.php

		# If default model is selected
		if [ "${DEFAULT_DATA_MODEL}" = "1" ]; then
			drush wisski-core:import-ontology --store="default" --ontology_url="https://wiss-ki.eu/ontology/" --reasoning
			composer require soda-collection-objects-data-literacy/wisski_sweet:dev-main
      composer unpack soda-collection-objects-data-literacy/wisski_sweet
      drush recipe ../recipes/wisski_sweet
      drush cr
      drush wisski-core:recreate-menus
      drush cr
		fi

		# Set permissions
		chown -R www-data:www-data /opt/drupal

	else
		echo "/opt/drupal/web already exists. So nothing was installed."
fi

# Adjust permissions and links
	rm -r /var/www/html
	ln -sf /opt/drupal/web /var/www/html

# Show apache log and keep server running
/usr/sbin/apache2ctl -D FOREGROUND
