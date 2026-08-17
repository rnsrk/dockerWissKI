#!/bin/bash
# Use this instead of raw `composer require` so extra packages are recorded
# in the persistent sites volume (composer.local.json) and survive image upgrades.
set -euo pipefail
cd /opt/drupal
composer "$@"
cmd="${1:-}"
case "${cmd}" in
  require|remove|update)
    php /usr/local/lib/wisski/sync-composer-local.php
    ;;
esac
