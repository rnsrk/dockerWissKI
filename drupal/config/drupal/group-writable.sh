#!/bin/bash
# Development only: make the files Composer extracted from zip archives
# group-writable, so `developer` (group www-data) can edit them. Those files
# keep their 644/755 modes even under umask 002 (git checkouts do not).
# Only files that lack group write are touched; the rest is a read-only scan.
set -euo pipefail

[ "${MODE:-}" = "development" ] || exit 0

find /opt/drupal -xdev ! -type l ! -perm -g=w \
  -not -path '*/node_modules/*' -not -path '*/.git/objects/*' \
  -not -path '/opt/drupal/web/sites/*' -exec chmod g+w {} +
