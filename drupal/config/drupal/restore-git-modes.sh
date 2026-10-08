#!/bin/bash
# Re-apply the executable bit to files that git tracks as 100755.
# A blanket `chmod 644` over the codebase strips it from every Composer
# source checkout (e.g. the WissKI clone), so `git status` lists hundreds
# of mode-only changes.
#
# Usage: restore-git-modes.sh [root]   (default: /opt/drupal)

set -euo pipefail

root="${1:-/opt/drupal}"

find "${root}" -path '*/node_modules' -prune -o -name .git -print0 -prune |
  while IFS= read -r -d '' gitPath; do
    repo="$(dirname "${gitPath}")"
    git -C "${repo}" ls-files --stage -z | while IFS= read -r -d '' entry; do
      if [ "${entry%% *}" = "100755" ]; then
        file="${repo}/${entry#*$'\t'}"
        if [ -f "${file}" ] && [ ! -L "${file}" ]; then
          chmod a+x "${file}"
        fi
      fi
    done
  done
