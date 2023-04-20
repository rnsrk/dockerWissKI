
#!/bin/bash

# Entrypoint to install Drupal in container

# Check if installation already exists
if ! [ -d /opt/drupal/web ]
	then
		# https://www.drupal.org/node/3060/release
		DRUPAL_VERSION='9.5.8'

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
			drupal/wisski"

		# Install Drupal, WissKI and dependencies
		set -eux
		export COMPOSER_HOME="$(mktemp -d)"
		composer create-project --no-interaction "drupal/recommended-project:$DRUPAL_VERSION" ./
		yes | composer require ${REQUIREMENTS}

		# Adjust permissions and links 
		chown -R www-data:www-data /opt/drupal
		rm -r /var/www/html
		ln -sf /opt/drupal/web /var/www/html

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

		# Move settings-file to the right place
		mv /settings.php web/sites/default/settings.php
		
		# Set permissions
		chmod -R 644 web/sites/default/settings.php
		chown -R www-data:www-data /opt/drupal		
	else
		echo "/opt/drupal/web already exists."
	fi

# Show apache log and keep server running
/usr/sbin/apache2ctl -D FOREGROUND