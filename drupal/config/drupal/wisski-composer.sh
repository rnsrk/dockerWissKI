#!/bin/bash
# Use this instead of raw `composer require` so extra packages are recorded
# in the persistent sites volume (composer.local.json) and survive image upgrades.
set -euo pipefail
# Composer runs as root. In development the `developer` user (group www-data)
# edits the same tree, so new files should be group-writable (see
# group-writable.sh for the files that umask cannot fix).
umask 002
cd /opt/drupal
composer "$@"
cmd="${1:-}"
case "${cmd}" in
  require|remove|update)
    php /usr/local/lib/wisski/sync-composer-local.php
    /usr/local/bin/group-writable.sh
    ;;
esac
