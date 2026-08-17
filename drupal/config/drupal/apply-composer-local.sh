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

cp "${BAKED_JSON}" "${ROOT}/composer.json"
if [ -f "${BAKED_LOCK}" ]; then
  cp "${BAKED_LOCK}" "${ROOT}/composer.lock"
else
  rm -f "${ROOT}/composer.lock"
fi

if [ ! -f "${LOCAL_JSON}" ]; then
  echo "No composer.local.json; using image packages only."
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
  exit 0
fi

echo "Applying extra Composer packages from composer.local.json:"
printf '  - %s\n' "${packages[@]}"

composer require \
  --no-interaction \
  --no-progress \
  --update-no-dev \
  --update-with-dependencies \
  "${packages[@]}"
