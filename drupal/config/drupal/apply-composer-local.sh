#!/bin/bash
# Re-apply site-specific Composer packages onto the image codebase.
# The image composer.json/lock are restored first so a new image is never
# shadowed by an old persisted lock file. Extras live in
# web/sites/composer.local.json (sites volume).

set -euo pipefail

ROOT="/opt/drupal"
LOCAL_JSON="${ROOT}/web/sites/composer.local.json"
BAKED_JSON="${ROOT}/.wisski-composer.json"
BAKED_LOCK="${ROOT}/.wisski-composer.lock"

cd "${ROOT}"

if [ ! -f "${BAKED_JSON}" ]; then
  echo "Baked composer.json missing; skipping extra packages."
  exit 0
fi

# Stamp lives in the container layer (next to vendor), not on the sites volume.
# Recreating the container drops it so extras are applied onto a fresh image.
# Restarting the same container skips a ~8s composer require.
STAMP_FILE="${ROOT}/.wisski-composer-local.stamp"
image_ver="$(cat "${ROOT}/.wisski-packages-version" 2>/dev/null || echo unknown)"
baked_hash="$(md5sum "${BAKED_JSON}" | awk '{print $1}')"
if [ -f "${LOCAL_JSON}" ]; then
  local_hash="$(md5sum "${LOCAL_JSON}" | awk '{print $1}')"
else
  local_hash="none"
fi
wanted="${image_ver}:${baked_hash}:${local_hash}"
if [ -f "${STAMP_FILE}" ] && [ "$(cat "${STAMP_FILE}")" = "${wanted}" ]; then
  echo "Site Composer packages already applied; skipping."
  exit 0
fi

cp "${BAKED_JSON}" "${ROOT}/composer.json"
if [ -f "${BAKED_LOCK}" ]; then
  cp "${BAKED_LOCK}" "${ROOT}/composer.lock"
else
  rm -f "${ROOT}/composer.lock"
fi

write_stamp() {
  printf '%s\n' "${wanted}" > "${STAMP_FILE}"
}

if [ ! -f "${LOCAL_JSON}" ]; then
  echo "No composer.local.json; using image packages only."
  write_stamp
  exit 0
fi

if ! php -r 'exit(@json_decode(file_get_contents($argv[1])) ? 0 : 1);' "${LOCAL_JSON}"; then
  echo "ERROR: ${LOCAL_JSON} is not valid JSON." >&2
  exit 1
fi

mapfile -t packages < <(php -r '
$j = json_decode(file_get_contents($argv[1]), true) ?: [];
foreach ($j["require"] ?? [] as $name => $constraint) {
  if ($name === "php" || str_starts_with($name, "ext-")) {
    continue;
  }
  echo $name . ":" . $constraint, PHP_EOL;
}
' "${LOCAL_JSON}")

if [ "${#packages[@]}" -eq 0 ]; then
  echo "composer.local.json has no extra require entries."
  write_stamp
  exit 0
fi

echo "Applying extra Composer packages from composer.local.json:"
printf '  - %s\n' "${packages[@]}"

# --update-no-dev uninstalls require-dev (phpcs, phpstan, …). The development
# image bakes those into .wisski-composer.json; keep them when present.
composer_args=(
  --no-interaction
  --no-progress
  --update-with-dependencies
)
if ! php -r 'exit(!empty(json_decode(file_get_contents($argv[1]), true)["require-dev"] ?? []) ? 0 : 1);' "${BAKED_JSON}"; then
  composer_args+=(--update-no-dev)
fi

composer require \
  "${composer_args[@]}" \
  "${packages[@]}"

write_stamp
