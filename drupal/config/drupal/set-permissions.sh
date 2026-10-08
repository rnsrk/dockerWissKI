#!/bin/bash
# Lock down the generated settings files and make the state directories
# writable for PHP-FPM. The codebase (core, vendor, modules) belongs to root
# and is baked into the image; nothing here touches it. Cheap and idempotent,
# so the entrypoint runs it on every boot.
# See https://www.drupal.org/docs/administering-a-drupal-site/security-in-drupal/securing-file-permissions-and-ownership
set -e

WEB_ROOT="/opt/drupal/web"
PRIVATE_FILES_DIR="${DRUPAL_PRIVATE_FILES_DIR:-/opt/drupal/private-files}"

# Settings files are read-only and owned by root, so PHP-FPM cannot rewrite
# them. Development keeps sites/default group-writable (775, group www-data)
# so `developer` can add settings.local.php.
if [ "${MODE}" = "development" ]; then
  sites_default_mode=775
else
  sites_default_mode=555
fi
if [ -d "${WEB_ROOT}/sites/default" ]; then
  chown root:www-data "${WEB_ROOT}/sites/default"
  for file in settings.php services.yml settings.local.php; do
    if [ -f "${WEB_ROOT}/sites/default/${file}" ]; then
      chown root:www-data "${WEB_ROOT}/sites/default/${file}"
      chmod 444 "${WEB_ROOT}/sites/default/${file}"
    fi
  done
  chmod "${sites_default_mode}" "${WEB_ROOT}/sites/default"
fi

# Public and private files belong to PHP-FPM. Walk them once, after the install
# created them; a recursive chown on every boot is slow with many uploads.
for dir in "${WEB_ROOT}/sites/default/files" "${PRIVATE_FILES_DIR}"; do
  if [ -d "${dir}" ] && [ "$(stat -c %U "${dir}")" != "www-data" ]; then
    chown -R www-data:www-data "${dir}"
    find "${dir}" -type d -exec chmod 775 {} +
    find "${dir}" -type f -exec chmod 664 {} +
  fi
done

echo "Permissions set: settings files 444, sites/default ${sites_default_mode}, files directories owned by www-data."
