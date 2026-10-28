#!/bin/bash
# Container entrypoint (tini starts it as PID 1's child). On every start it:
#   1. prepares the development user and the volumes,
#   2. installs the site on the first start, or brings an existing one up to date,
#   3. starts memcached, iipsrv, PHP-FPM, and nginx.
# main at the bottom lists the steps in order.

set -e

# Trace every command only when explicitly requested (floods compose logs).
if [ "${ENTRYPOINT_DEBUG:-}" = "1" ] || [ "${ENTRYPOINT_DEBUG:-}" = "true" ]; then
  set -x
fi

export COMPOSER_HOME=/var/composer-home

# Canonical path (do not use /var/www/html/sites/...). The php/nginx images
# ship /var/www/html as a directory; a failed symlink would make this miss
# the sites volume and skip the SALZ sync on every boot.
SETTINGS_FILE="/opt/drupal/web/sites/default/settings.php"
export SETTINGS_FILE

# Marker files that gate the install logic across container restarts. They
# live in the sites volume because the rest of /opt/drupal is the image's
# codebase, which does not persist across recreations.
INSTALL_COMPLETE_FILE="/opt/drupal/web/sites/.wisski-install-complete"
INSTALL_IN_PROGRESS_FILE="/opt/drupal/web/sites/.wisski-install-in-progress"

# Package set version baked into the image and the version the sites volume
# was last updated to (a difference triggers drush updatedb after an upgrade).
IMAGE_PACKAGES_VERSION_FILE="/opt/drupal/.wisski-packages-version"
SITE_PACKAGES_VERSION_FILE="/opt/drupal/web/sites/.wisski-packages-version"

# Private files live outside the web root and are mounted as a volume.
DRUPAL_PRIVATE_FILES_DIR="${DRUPAL_PRIVATE_FILES_DIR:-/opt/drupal/private-files}"

WISSKI_MODULE_DIR="/opt/drupal/web/modules/contrib/wisski"
WISSKI_SCS_BASE_DIR="/opt/drupal/repos/wisski"

# --- Log helpers -------------------------------------------------------------
step() { echo -e "\033[0;33m$*\033[0m"; }
ok()   { echo -e "\033[0;32m$*\033[0m\n"; }
warn() { echo -e "\033[0;33mWARNING: $*\033[0m"; }
err()  { echo -e "\033[0;31mERROR: $*\033[0m"; }

# Entrypoint Drush must not pay Xdebug overhead. php-fpm is started later and
# does not inherit this function, so IDE debugging on port 9003 still works.
drush() {
  XDEBUG_MODE=off command drush "$@"
}

is_development() {
  [ "${MODE}" = "development" ]
}

# --- Start-up checks and preparation ----------------------------------------
banner() {
  echo -e "\n \n \n"
  echo -e "\033[38;5;208mWW      WW   iii   sss   sss   KK   KK   III\033[0m"
  echo -e "\033[38;5;208mWW      WW   iii   sss   sss   KK  KK    III\033[0m"
  echo -e "\033[38;5;208mWW      WW   iii  ss    ss     KK KK     III\033[0m"
  echo -e "\033[38;5;208m WW WW WW    iii   sss   sss   KKKK      III\033[0m"
  echo -e "\033[38;5;208m WW WW WW    iii     ss    ss  KK KK     III\033[0m"
  echo -e "\033[38;5;208m  WW  WW     iii   sss   sss   KK  KK    III\033[0m"
  echo -e "\033[38;5;208m  WW  WW     iii   sss   sss   KK   KK   III\033[0m"
  echo -e "\n"
  echo -e "\033[0;32m+------------------------------+\033[0m"
  echo -e "\033[0;32m|WISSKI ENVIRONMENT ENTRYPOINT.|\033[0m"
  echo -e "\033[0;32m+------------------------------+\033[0m"
  echo -e "\n"
  if is_development; then
    echo -e "\033[0;32mDEVELOPMENT MODE ENABLED.\033[0m"
  fi
  echo "USER: $(whoami)"
  echo "PWD: $(pwd)"
}

# Development: keep `developer` on the host UID so bind-mounted ~/.ssh and a
# host WissKI clone are writable without copying keys. PID 1 stays root.
prepare_developer_user() {
  if ! is_development || ! id developer >/dev/null 2>&1; then
    return 0
  fi

  local uid="${DEV_UID:-1000}" gid="${DEV_GID:-1000}"
  case "${uid}" in
    0|33)
      step "DEV_UID=${uid} is reserved (root/www-data); leaving developer unchanged."
      ;;
    *)
      if [ "$(id -u developer)" != "${uid}" ]; then
        usermod -u "${uid}" developer
      fi
      if [ "$(id -g developer)" != "${gid}" ]; then
        if getent group "${gid}" >/dev/null; then
          usermod -g "${gid}" developer
          # PHP-FPM writes into the test sites `developer` creates.
          usermod -aG "$(getent group "${gid}" | cut -d: -f1)" www-data
        else
          groupmod -g "${gid}" developer
        fi
      fi
      ;;
  esac
  chown developer:developer /home/developer

  # Named IDE volumes start as root. Do not recurse into :ro binds (Machine
  # settings.json, Cursor/Claude rules/skills/agents): they are the same
  # filesystem as the volume, so find -xdev would still try chown and spam EROFS.
  local root
  for root in /home/developer/.cursor-server /home/developer/.vscode-server \
              /home/developer/.cursor /home/developer/.claude; do
    mkdir -p "${root}"
    chown developer:developer "${root}" 2>/dev/null || true
    find "${root}" \( \
      -path "${root}/rules" -o \
      -path "${root}/skills" -o \
      -path "${root}/agents" -o \
      -path "/home/developer/.claude/settings.json" -o \
      -path "${root}/data/Machine/settings.json" \
    \) -prune -o -exec chown developer:developer {} + 2>/dev/null || true
  done
}

# Recipe versions are baked into the image. WISSKI_STARTER_VERSION and
# WISSKI_DEFAULT_DATA_MODEL_VERSION are optional flags (non-empty = apply).
validate_environment() {
  step "VALIDATING ENVIRONMENT VARIABLES..."
  local required=(
    DB_DRIVER DB_HOST DB_NAME DB_PASSWORD DB_PORT DB_USER
    DRUPAL_DOMAIN DRUPAL_LOCALE DRUPAL_PASSWORD DRUPAL_PRIVATE_FILES_DIR
    DRUPAL_SITE_NAME DRUPAL_TRUSTED_HOSTS DRUPAL_USER
    REDIS_HOST REDIS_PORT
    TS_REPOSITORY TS_READ_URL TS_WRITE_URL TS_USERNAME TS_PASSWORD
    WISSKI_DEFAULT_GRAPH
  )
  local missing=() var
  for var in "${required[@]}"; do
    if [ -z "${!var}" ]; then
      missing+=("${var}")
    fi
  done
  if [ ${#missing[@]} -ne 0 ]; then
    err "Missing required environment variables:"
    for var in "${missing[@]}"; do
      echo -e "\033[0;31m  - ${var}\033[0m"
    done
    exit 1
  fi
  ok "ALL REQUIRED ENVIRONMENT VARIABLES ARE SET."

  if is_development; then
    step "ENVIRONMENT VARIABLES:"
    env | sort | grep -viE 'PASSWORD|SECRET|TOKEN|KEY|GPG|SIMPLETEST_DB' || true
    echo
  fi
}

# The volumes start out root-owned. PHP-FPM (www-data) writes to all of them.
prepare_volumes() {
  chown www-data:www-data /opt/drupal/web/sites 2>/dev/null || true
  mkdir -p "${DRUPAL_PRIVATE_FILES_DIR}" /opt/drupal/web/modules/custom /opt/drupal/web/themes/custom
  chown www-data:www-data "${DRUPAL_PRIVATE_FILES_DIR}" /opt/drupal/web/modules/custom /opt/drupal/web/themes/custom
}

# Development: `developer` is in www-data and edits via group write + setgid.
# The image tree is group-writable from build time (umask 002, setgid). Only
# the volume mount points start out root-owned without group write.
ensure_dev_group_write() {
  if ! is_development || ! id developer >/dev/null 2>&1; then
    return 0
  fi
  chmod g+ws /opt/drupal/web/sites "${DRUPAL_PRIVATE_FILES_DIR}"
  chmod -R g+w /opt/drupal/web/modules/custom /opt/drupal/web/themes/custom
  find /opt/drupal/web/modules/custom /opt/drupal/web/themes/custom -type d -exec chmod g+s {} +
}

# --- WissKI clone (development) ---------------------------------------------
# The WissKI clone sits on its own volume (named volume from
# docker-compose.development.yml, or a host bind from the override) so
# branches, remotes, vendor/ and node_modules/ survive recreation and image
# pulls. Docker seeds an empty named volume from the image; an empty host bind
# is cloned here at the commit the image was built with.
# Prints "<git url> <commit>" of the drupal/wisski package the image installed.
wisski_package_source() {
  php -r '
    $installed = json_decode((string) file_get_contents("/opt/drupal/vendor/composer/installed.json"), true);
    foreach ($installed["packages"] ?? [] as $package) {
      if ($package["name"] === "drupal/wisski" && isset($package["source"]["url"])) {
        echo $package["source"]["url"], " ", $package["source"]["reference"] ?? "";
      }
    }
  '
}

seed_wisski_clone() {
  local url ref tmp
  read -r url ref <<< "$(wisski_package_source)"
  if [ -z "${url}" ]; then
    err "${WISSKI_MODULE_DIR} is empty and the image has no WissKI source URL to clone from."
    return 1
  fi

  step "SEEDING WISSKI CLONE INTO ${WISSKI_MODULE_DIR} (${url} @ ${ref:-HEAD})..."
  tmp="$(mktemp -d /tmp/wisski-seed.XXXXXX)"
  chown developer "${tmp}"
  # The system gitconfig rewrites drupalcode HTTPS to SSH; seeding must work
  # without keys, so clone over HTTPS and let later fetch/push use SSH.
  if ! su developer -s /bin/bash -c "GIT_CONFIG_NOSYSTEM=1 git clone --quiet '${url}' '${tmp}/wisski'"; then
    rm -rf "${tmp}"
    err "Could not clone ${url} into ${WISSKI_MODULE_DIR}."
    return 1
  fi
  if [ -n "${ref}" ] && ! su developer -s /bin/bash -c "git -C '${tmp}/wisski' reset --quiet --hard '${ref}'"; then
    warn "${ref} not found upstream; WissKI clone stays on the default branch HEAD."
  fi
  cp -a "${tmp}/wisski/." "${WISSKI_MODULE_DIR}/"
  rm -rf "${tmp}"
  chown developer:www-data "${WISSKI_MODULE_DIR}"
  ok "WISSKI CLONE SEEDED."
}

ensure_wisski_dev_clone() {
  if ! is_development || ! id developer >/dev/null 2>&1; then
    return 0
  fi

  mkdir -p "${WISSKI_MODULE_DIR}"
  if [ ! -f "${WISSKI_MODULE_DIR}/wisski.info.yml" ]; then
    seed_wisski_clone || exit 1
  fi

  if [ -f "${WISSKI_MODULE_DIR}/package.json" ] \
    && [ ! -x "${WISSKI_MODULE_DIR}/node_modules/.bin/cspell" ] \
    && command -v corepack >/dev/null 2>&1; then
    step "INSTALLING WISSKI JS LINT TOOLS (yarn install)..."
    if su developer -s /bin/bash -c "cd '${WISSKI_MODULE_DIR}' && corepack yarn install --immutable"; then
      ok "WISSKI JS LINT TOOLS INSTALLED."
    else
      warn "yarn install failed in ${WISSKI_MODULE_DIR}; cspell/eslint/stylelint are unavailable."
    fi
  fi

  if [ -d "${WISSKI_MODULE_DIR}/vendor/drupal/core" ]; then
    warn "${WISSKI_MODULE_DIR}/vendor contains a second drupal/core (pulled in by drupal/potx)."
    echo "PHPStan then aborts with \"Cannot redeclare t()\". The lint and test tools are in /opt/drupal/vendor;"
    echo "remove ${WISSKI_MODULE_DIR}/vendor so misc/scripts/*.sh use them."
  fi
}

# Read-only scs_base clone that the agent skills compare 8.x-4.x work against
# (compare-scs-base, issue-solve). It sits on its own volume; a missing clone is
# cloned here. Without network the container still starts, only the compare
# falls back to `git show origin/scs_base` in the work clone.
ensure_wisski_scs_base_clone() {
  local url tmp
  if ! is_development || ! id developer >/dev/null 2>&1; then
    return 0
  fi

  mkdir -p "${WISSKI_SCS_BASE_DIR}"
  chown developer:www-data "${WISSKI_SCS_BASE_DIR}"
  if [ -d "${WISSKI_SCS_BASE_DIR}/.git" ]; then
    return 0
  fi

  read -r url _ <<< "$(wisski_package_source)"
  if [ -z "${url}" ]; then
    warn "No WissKI source URL in the image; ${WISSKI_SCS_BASE_DIR} stays empty."
    return 0
  fi

  step "CLONING WISSKI scs_base INTO ${WISSKI_SCS_BASE_DIR}..."
  tmp="$(mktemp -d /tmp/wisski-scs-base.XXXXXX)"
  chown developer "${tmp}"
  # HTTPS without the system gitconfig, as in seed_wisski_clone: no keys needed.
  if su developer -s /bin/bash -c "GIT_CONFIG_NOSYSTEM=1 git clone --quiet --branch scs_base '${url}' '${tmp}/wisski'"; then
    cp -a "${tmp}/wisski/." "${WISSKI_SCS_BASE_DIR}/"
    ok "WISSKI scs_base CLONED."
  else
    warn "Could not clone scs_base from ${url}; ${WISSKI_SCS_BASE_DIR} stays empty until the next start."
  fi
  rm -rf "${tmp}"
}

# --- Settings generated from the environment --------------------------------
# Quote a value as a single-quoted PHP string.
php_quote() {
  local value="${1//\\/\\\\}"
  value="${value//\'/\\\'}"
  printf "'%s'" "${value}"
}

# Trusted reverse proxies as a pipe-separated list, empty when disabled.
#   unset, none, off, false, 0: no reverse proxy (standalone stack)
#   auto: the networks of this container, which Caddy and Varnish share
#   anything else is used as given, e.g. 172.20.0.0/16|192.168.64.0/20
proxy_addresses() {
  case "${DRUPAL_PROXY_ADDRESSES:-}" in
    ''|none|off|false|0) ;;
    auto) ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | sort -u | paste -sd'|' - ;;
    *) printf '%s' "${DRUPAL_PROXY_ADDRESSES}" ;;
  esac
}

# Everything the environment decides about settings.php goes into
# settings.docker.php, which is rewritten on every start, so changes in .env
# (trusted hosts, proxy addresses) take effect without editing settings.php.
# settings.php only includes that file, once.
write_docker_settings() {
  local file addresses pattern address patterns parts
  file="$(dirname "${SETTINGS_FILE}")/settings.docker.php"
  addresses="$(proxy_addresses)"
  if [ "${DRUPAL_PROXY_ADDRESSES:-}" = "auto" ] && [ -z "${addresses}" ]; then
    warn "DRUPAL_PROXY_ADDRESSES=auto found no global IPv4 network; reverse proxy settings stay off."
  fi

  {
    cat <<'PHP'
<?php

/**
 * Generated by the container entrypoint on every start. Change .env
 * (DRUPAL_TRUSTED_HOSTS, DRUPAL_PRIVATE_FILES_DIR, DRUPAL_PROXY_ADDRESSES),
 * not this file.
 */

PHP
    echo "\$settings['trusted_host_patterns'] = ["
    IFS='|' read -ra patterns <<< "${DRUPAL_TRUSTED_HOSTS}"
    for pattern in "${patterns[@]}"; do
      echo "  $(php_quote "${pattern}"),"
    done
    echo "];"
    echo "\$settings['file_private_path'] = $(php_quote "${DRUPAL_PRIVATE_FILES_DIR}");"
    cat <<'PHP'

// Redis cache backend. include_once, because older sites still include it
// from settings.php as well.
include_once '/var/configs/redis.settings.php';

PHP
    if [ -n "${addresses}" ]; then
      echo "\$settings['reverse_proxy'] = TRUE;"
      cat <<'PHP'
$settings['reverse_proxy_trusted_headers'] = \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_FOR | \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_HOST | \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_PORT | \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_PROTO;
$settings['omit_vary_cookie'] = TRUE;
PHP
      echo "\$settings['reverse_proxy_addresses'] = ["
      IFS='|' read -ra parts <<< "${addresses}"
      for address in "${parts[@]}"; do
        address="${address//[[:space:]]/}"
        if [ -n "${address}" ]; then
          echo "  $(php_quote "${address}"),"
        fi
      done
      echo "];"
    else
      echo "\$settings['reverse_proxy'] = FALSE;"
    fi
  } > "${file}"

  if ! grep -q 'settings.docker.php' "${SETTINGS_FILE}"; then
    cat >> "${SETTINGS_FILE}" <<'PHP'

/**
 * Settings generated by the container entrypoint on every start.
 */
if (file_exists($app_root . '/' . $site_path . '/settings.docker.php')) {
  include $app_root . '/' . $site_path . '/settings.docker.php';
}
PHP
  fi
  ok "DOCKER SETTINGS WRITTEN (reverse proxy: ${addresses:-off})."
}

# --- Triplestore and database ------------------------------------------------
# OpenGDB does not create repositories at its own start. When GET
# /rest/repositories does not already list TS_REPOSITORY, Drupal POSTs it
# once (Django row + RDF4J store) and waits until SPARQL ASK returns HTTP 200.
# A second POST inserts another Django row with the same slug. Permission
# creation then hits UNIQUE, the row stays, and every later lookup of that
# slug returns HTTP 500. Auth is HTTP Basic: TS_USERNAME / TS_PASSWORD (same
# as the OpenGDB superuser). Do not put SPARQL tokens in .env.
#
# Status: 0 slug is listed, 1 list is HTTP 200 and the slug is absent,
# 2 the list could not be read.
triplestore_repository_listed() {
  local list_file="$1"
  local list_url="$2"
  local list_code

  list_code="$(curl -sS -o "${list_file}" -w '%{http_code}' \
    -u "${TS_USERNAME}:${TS_PASSWORD}" "${list_url}" || true)"
  if [ "${list_code}" != "200" ]; then
    return 2
  fi
  php -r '
    $raw = stream_get_contents(STDIN);
    $repos = json_decode($raw, true);
    if (!is_array($repos)) {
      fwrite(STDERR, "OpenGDB repository list is not a JSON array.\n");
      exit(2);
    }
    $want = getenv("TS_REPOSITORY");
    foreach ($repos as $repo) {
      if (is_array($repo) && ($repo["id"] ?? "") === $want) {
        exit(0);
      }
    }
    exit(1);
  ' < "${list_file}"
}

ensure_default_triplestore() {
  local ts_auth=(-u "${TS_USERNAME}:${TS_PASSWORD}")
  local ts_base ts_rest ts_body list_body
  local attempt=0 max_attempts=45
  local post_code="skipped" ask_code listed_status=0
  local reported_existing=0 posted=0

  ts_base="$(printf '%s' "${TS_READ_URL}" | sed -E 's#(https?://[^/]+).*#\1#')"
  ts_rest="${ts_base}/rest/repositories"
  ts_body="$(mktemp)"
  list_body="$(mktemp)"

  ask_code="$(curl -sS -o /dev/null -w '%{http_code}' "${ts_auth[@]}" \
    --get --data-urlencode 'query=ASK { }' "${TS_READ_URL}" || true)"
  if [ "${ask_code}" = "200" ]; then
    rm -f "${ts_body}" "${list_body}"
    ok "DEFAULT TRIPLESTORE REPOSITORY READY."
    return 0
  fi

  step "ENSURING DEFAULT TRIPLESTORE REPOSITORY (${TS_REPOSITORY} via ${ts_rest})..."
  while [ "${attempt}" -lt "${max_attempts}" ]; do
    listed_status=0
    triplestore_repository_listed "${list_body}" "${ts_rest}" || listed_status=$?
    if [ "${listed_status}" -eq 1 ] && [ "${posted}" -eq 0 ]; then
      post_code="$(curl -sS -o "${ts_body}" -w '%{http_code}' -X POST "${ts_rest}" "${ts_auth[@]}" \
        -H 'Content-Type: application/json' \
        --data "{\"id\":\"${TS_REPOSITORY}\",\"title\":\"The default repository\"}" || true)"
      # Any HTTP answer may already have inserted the row (OpenGDB commits
      # before permission creation fails with 400). Do not post again.
      if [ -n "${post_code}" ] && [ "${post_code}" != "000" ]; then
        posted=1
      fi
      step "OpenGDB: POST ${ts_rest} -> HTTP ${post_code:-000} (slug was absent)"
    elif [ "${listed_status}" -eq 0 ]; then
      post_code="skipped"
      if [ "${reported_existing}" -eq 0 ]; then
        step "OpenGDB already lists ${TS_REPOSITORY}; waiting for SPARQL."
        reported_existing=1
      fi
    else
      post_code="skipped"
    fi

    ask_code="$(curl -sS -o /dev/null -w '%{http_code}' "${ts_auth[@]}" \
      --get --data-urlencode 'query=ASK { }' "${TS_READ_URL}" || true)"
    step "OpenGDB: SPARQL ASK -> HTTP ${ask_code:-000} (attempt $((attempt + 1))/${max_attempts})"
    if [ "${ask_code}" = "200" ]; then
      rm -f "${ts_body}" "${list_body}"
      ok "DEFAULT TRIPLESTORE REPOSITORY READY."
      return 0
    fi
    sleep 2
    attempt=$((attempt + 1))
  done

  err "SPARQL ASK at ${TS_READ_URL} did not return HTTP 200."
  if [ -s "${ts_body}" ]; then
    step "Last POST ${ts_rest} body:"
    cat "${ts_body}" 2>/dev/null || true
  fi
  rm -f "${ts_body}" "${list_body}"
  return 1
}

wait_for_database() {
  step "CHECKING DATABASE CONNECTION..."
  local attempt max_attempts=30
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if PGPASSWORD="${DB_PASSWORD}" pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
      ok "DATABASE CONNECTION SUCCESSFUL."
      return 0
    fi
    step "Waiting for database... (attempt ${attempt}/${max_attempts})"
    sleep 2
  done
  err "Could not connect to database after ${max_attempts} attempts."
  echo "DB_HOST: ${DB_HOST}  DB_PORT: ${DB_PORT}  DB_USER: ${DB_USER}  DB_NAME: ${DB_NAME}"
  return 1
}

# Development: what the WissKI PHPUnit tests need from this container. The
# browser, the file server and RDF4J are services of their own.
prepare_phpunit() {
  if ! is_development || ! id developer >/dev/null 2>&1; then
    return 0
  fi
  # Tests run as `developer`. Drupal creates sites/simpletest/<id> itself but
  # not the HTML output directory, and drops the page links without it.
  install -d -o developer -g www-data -m 2775 \
    /opt/drupal/web/sites/simpletest /opt/drupal/web/sites/simpletest/browser_output
  ensure_test_database
}

# The database SIMPLETEST_DB points PHPUnit at. Drupal puts every test site
# into prefixed tables there and, on PostgreSQL, needs pg_trgm as in the site
# database. Failing here only costs the tests.
ensure_test_database() {
  if [ -z "${DB_TEST_NAME:-}" ] || [ "${DB_DRIVER}" != "pgsql" ]; then
    return 0
  fi
  if ! [[ "${DB_TEST_NAME}" =~ ^[a-z_][a-z0-9_]*$ ]]; then
    warn "DB_TEST_NAME=${DB_TEST_NAME} is not a lowercase identifier; test database not created."
    return 0
  fi

  local psql=(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -v ON_ERROR_STOP=1 -qtA)
  if [ "$(PGPASSWORD="${DB_PASSWORD}" "${psql[@]}" -d "${DB_NAME}" \
    -c "SELECT 1 FROM pg_database WHERE datname = '${DB_TEST_NAME}'")" != "1" ]; then
    step "CREATING TEST DATABASE ${DB_TEST_NAME}..."
    if ! PGPASSWORD="${DB_PASSWORD}" "${psql[@]}" -d "${DB_NAME}" -c "CREATE DATABASE ${DB_TEST_NAME}"; then
      warn "Could not create ${DB_TEST_NAME}; PHPUnit functional tests will not run."
      return 0
    fi
  fi
  if ! PGPASSWORD="${DB_PASSWORD}" PGOPTIONS='-c client_min_messages=warning' \
    "${psql[@]}" -d "${DB_TEST_NAME}" -c 'CREATE EXTENSION IF NOT EXISTS pg_trgm'; then
    warn "Could not enable pg_trgm in ${DB_TEST_NAME}; PHPUnit functional tests will not run."
    return 0
  fi
  ok "TEST DATABASE ${DB_TEST_NAME} READY."
}

# key_value_expire is created lazily on write. update_storage_clear() DELETEs
# it from hook_modules_installed. Postgres logs ERROR even though Drupal
# swallows the missing-table exception.
ensure_key_value_expire() {
  if [ ! -f "${SETTINGS_FILE}" ]; then
    return 0
  fi
  drush php-eval '
    $schema = \Drupal::database()->schema();
    if (!$schema->tableExists("key_value_expire")) {
      $schema->createTable("key_value_expire", \Drupal\Core\KeyValueStore\DatabaseStorageExpirable::schemaDefinition());
    }
  ' >/dev/null
}

# Drupal 11.4's standard profile no longer creates the Basic page and Article
# content types; core ships them as recipes. The default data model recipe
# needs Basic page, and sites installed before had both.
ensure_basic_content_types() {
  local type
  for type in page article; do
    if drush php-eval "exit(\\Drupal\\node\\Entity\\NodeType::load('${type}') ? 0 : 1);" >/dev/null 2>&1; then
      continue
    fi
    step "CREATE CONTENT TYPE ${type}."
    drush recipe "core/recipes/${type}_content_type" >/dev/null
    ok "CONTENT TYPE ${type} CREATED."
  done
}

# Keep the default SALZ adapter on TS_READ_URL / TS_WRITE_URL (authproxy, not OpenGDB nginx).
sync_salz_adapter_urls() {
  if [ ! -f "${SETTINGS_FILE}" ]; then
    return 0
  fi
  step "SYNCING SALZ ADAPTER ENDPOINTS (${TS_READ_URL})..."
  if drush php-eval '
    $read = getenv("TS_READ_URL");
    $write = getenv("TS_WRITE_URL");
    if ($read === false || $read === "" || $write === false || $write === "") {
      return;
    }
    $adapter = \Drupal::entityTypeManager()->getStorage("wisski_salz_adapter")->load("default");
    if (!$adapter) {
      return;
    }
    $config = $adapter->getEngine()->getConfiguration();
    if (($config["read_url"] ?? "") === $read && ($config["write_url"] ?? "") === $write) {
      return;
    }
    $config["read_url"] = $read;
    $config["write_url"] = $write;
    $adapter->setEngineConfig($config);
    $adapter->save();
  '; then
    ok "SALZ ADAPTER ENDPOINTS SYNCED."
  else
    warn "SALZ adapter endpoint sync skipped."
  fi
}

# wisski_mirador pins a release of the WissKI Mirador Integration library.
# web/libraries is part of the image tree, so install or update the pinned
# release on every start; the command does nothing when it is already there.
# The if keeps a failed download from aborting the boot under set -e.
ensure_mirador_library() {
  if ! drush pm:list --status=enabled --type=module --field=name 2>/dev/null | grep -qx wisski_mirador; then
    return 0
  fi
  step "ENSURE WISSKI MIRADOR LIBRARY."
  # As www-data, so the status report's update form can replace it later.
  if runuser -u www-data -- env XDEBUG_MODE=off drush --root=/opt/drupal wisski-mirador:wisski-mirador-integration; then
    ok "WISSKI MIRADOR LIBRARY READY."
  else
    warn "WissKI Mirador library could not be installed; the viewer stays empty until it is (status report)."
  fi
}

# --- First installation ------------------------------------------------------
# Entity bundle and field IDs the DLF AIM 3D Viewer module ships as its own
# defaults (config/install/dlf_aim_3d_viewer.settings.yml).
DLF_ENTITY_BUNDLE="bd3d7baa74856d141bcff7b4193fa128"
DLF_VIEWER_FILE_UPLOAD_FIELD="fbf95bddee5160d515b982b3fd2e05f7"
DLF_VIEWER_FILE_NAME_FIELD="faa602a0be629324806aef22892cdbe5"

# Permissions of the wisski_user role. One that this install does not define
# (for example from a module that is not part of the image) is skipped.
WISSKI_USER_PERMISSIONS=(
  'access toolbar'
  'access navigate'
  'access create'
  'access find'
  'create any wisski content'
  'view any wisski content'
  'view published wisski content'
  'view own unpublished wisski content'
  'view other unpublished wisski content'
  'view wisski revisions'
  'revert wisski revisions'
  'edit any wisski content'
  'delete any wisski content'
  'access wisski manifests'
  'wisski_adapter_sparql11_pb.query'
)

grant_wisski_user_permissions() {
  step "GRANTING WISSKI USER PERMISSIONS."
  if ! drush pm:list --status=enabled --type=module --filter=toolbar --format=list 2>/dev/null | grep -qx toolbar; then
    drush en toolbar -y || warn "toolbar module not enabled; access toolbar will be skipped."
  fi
  local perm
  for perm in "${WISSKI_USER_PERMISSIONS[@]}"; do
    drush role:perm:add wisski_user "${perm}" -y || warn "permission not defined, skipped: ${perm}"
  done
  ok "WISSKI USER PERMISSIONS GRANTED."
}

# German comes from the recipe's language config and the WissKI .po files.
# locale-check / locale-update are skipped on purpose: they download every
# contrib translation into the DB (minutes and gigabytes of WAL). Run
# `drush locale-update` later if you need them.
add_german_translations() {
  step "ADD GERMAN LANGUAGE AND IMPORT SHIPPED TRANSLATIONS."
  drush language-add de
  drush php-eval "
    \$source = new \Drupal\Core\Config\FileStorage('/opt/drupal/recipes/wisski_default_data_model/config/language/de');
    \$langStorage = \Drupal::service('config.storage')->createCollection('language.de');
    foreach (\$source->listAll() as \$name) {
      \$langStorage->write(\$name, \$source->read(\$name));
    }
  "
  find "${WISSKI_MODULE_DIR}" -name '*.de.po' -type f -print0 | while IFS= read -r -d '' po; do
    drush locale:import de "${po}" --type=not-customized --override=all -y
  done
  step "RECREATE WISSKI MAIN MENU."
  drush wisski-core:recreate-menus
  ok "TRANSLATIONS UPDATED."
}

# Disable the WissKI main menu links (menu: main). Config stores encoded keys
# (dots -> __), so use the API. Create, Navigate, and Find.
disable_wisski_main_menu_links() {
  step "DISABLE WISSKI MAIN MENU LINKS."
  drush php-eval "
    \$o = \\Drupal::service('menu_link.static.overrides');
    foreach (['wisski.create_entities', 'wisski.browse_entities', 'wisski.search_entities'] as \$id) {
      \$o->saveOverride(\$id, ['enabled' => FALSE]);
    }
  "
  ok "WISSKI MAIN MENU LINKS DISABLED."
}

configure_dlf_3d_viewer() {
  step "SET DLF AIM 3D VIEWER SETTINGS."
  drush dlf_aim_3d_viewer:configure \
    --main-url="https://${DRUPAL_DOMAIN}" \
    --container=DLF_AIM_3DViewer \
    --entitybundle="${DLF_ENTITY_BUNDLE}" \
    --viewer-file-upload="${DLF_VIEWER_FILE_UPLOAD_FIELD}" \
    --viewer-file-name="${DLF_VIEWER_FILE_NAME_FIELD}" \
    --lightweight=1 \
    --scale-container-x=1 \
    --scale-container-y=1.4 \
    --base-module-path=/libraries/dlf_aim_3d_viewer/dist/drupal/main/assets \
    --entity-id-uri='/wisski/navigate/(.*)/view' \
    --view-entity-path=/wisski/navigate/ \
    --attribute-id=wisski_id
  ok "DLF AIM 3D VIEWER SETTINGS SET."
}

# Everything that needs the triplestore and the WissKI default data model.
install_default_data_model() {
  step "INSTALL DEFAULT TRIPLESTORE ADAPTER."
  drush wisski-salz:create-adapter --type='sparql11_with_pb' --adapter_label='Default' --adapter_machine_name='default' --description='Default SALZ adapter' --ts_machine_name="${TS_REPOSITORY}" --ts_use_token=0 --ts_user="${TS_USERNAME}" --ts_password="${TS_PASSWORD}" --writable=1 --preferred=1 --read_url="${TS_READ_URL}" --write_url="${TS_WRITE_URL}" --federatable=0 --default_graph="${WISSKI_DEFAULT_GRAPH}" --same_as='http://www.w3.org/2002/07/owl#sameAs' >/dev/null
  drush cr
  ok "DEFAULT TRIPLESTORE ADAPTER INSTALLED."

  step "IMPORT WISSKI DEFAULT ONTOLOGY."
  drush wisski-core:import-ontology --store='default' --ontology_url='https://wiss-ki.eu/ontology/default/2.5.0/' --reasoning
  ok "WISSKI DEFAULT ONTOLOGY IMPORTED."

  # The recipe package is shipped in the image.
  step "APPLY WISSKI DEFAULT DATA MODEL RECIPE."
  drush recipe ../recipes/wisski_default_data_model
  ok "WISSKI DEFAULT DATA MODEL RECIPE APPLIED."

  add_german_translations
  disable_wisski_main_menu_links
  configure_dlf_3d_viewer

  step "SET IIIF CONFIGS."
  drush config-set wisski_iip_image.wisski_iiif_settings iiif_server "https://${DRUPAL_DOMAIN}/fcgi-bin/iipsrv.fcgi?IIIF="
  ok "IIIF CONFIGS SET."

  grant_wisski_user_permissions

  step "CLEAR CACHE."
  drush cr
  ok "CACHE CLEARED."
}

# IMCE profiles: members get their own folder, administrators the admin profile.
set_imce_profiles() {
  step "SET IMCE PROFILES."
  local pair role profile
  for pair in authenticated:member administrator:admin wisski_user:member; do
    role="${pair%%:*}"
    profile="${pair##*:}"
    drush config-set imce.settings "roles_profiles.${role}.public" "${profile}" -y >/dev/null
    drush config-set imce.settings "roles_profiles.${role}.private" "${profile}" -y >/dev/null
  done
  drush config-set --input-format=yaml imce.profile.member conf.folders '[{path: "users/user[user:name]", permissions: {all: true}}]' -y >/dev/null
  ok "IMCE PROFILES SET."
}

install_site() {
  ok "DRUPAL IS NOT INSTALLED."
  touch "${INSTALL_IN_PROGRESS_FILE}"

  wait_for_database || exit 1

  # Create OpenGDB `default` before recipes/SPARQL. Authproxy is already healthy.
  # If this fails, drop the in-progress marker so the next start can retry site-install.
  if ! ensure_default_triplestore; then
    rm -f "${INSTALL_IN_PROGRESS_FILE}"
    exit 1
  fi

  step "INSTALLING DRUPAL SITE..."
  if timeout 300 drush si \
    --db-url="${DB_DRIVER}://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
    --site-name="${DRUPAL_SITE_NAME}" \
    --account-name="${DRUPAL_USER}" \
    --account-pass="${DRUPAL_PASSWORD}" \
    --locale="${DRUPAL_LOCALE}" \
    --yes 2>&1; then
    ok "DRUPAL SITE \"${DRUPAL_SITE_NAME}\" INSTALLED."
    ensure_key_value_expire
    ensure_basic_content_types
  else
    err "Drupal installation failed or timed out after 5 minutes."
    echo "Check database connection and credentials."
    exit 1
  fi

  # Trusted hosts, private files path, Redis include, and reverse proxy.
  write_docker_settings

  # Page cache: Varnish in production; disabled in development so edits show immediately.
  if is_development; then
    drush config:set system.performance cache.page.max_age 0 -y >/dev/null
    ok "PAGE CACHE DISABLED (DEVELOPMENT)."
  else
    drush config:set system.performance cache.page.max_age 300 -y >/dev/null
    ok "PAGE CACHE ENABLED FOR VARNISH (5 minutes)."
  fi

  # Modules shipped in the image: single content sync, the health check
  # endpoint, and the Sophron MIME type guesser (from the imagemagick
  # dependency tree). devel must never run in production.
  local modules=(single_content_sync health_check sophron_guesser)
  if is_development; then
    modules+=(devel)
  fi
  step "ENABLE MODULES: ${modules[*]}."
  drush en "${modules[@]}" -y >/dev/null
  ok "MODULES ENABLED."

  step "CREATE WISSKI USER ROLE."
  drush role:create 'wisski_user' 'WissKI User' -y >/dev/null
  ok "WISSKI USER ROLE CREATED."

  # The recipe packages are shipped in the image.
  drush cr
  if [ -n "${WISSKI_STARTER_VERSION}" ]; then
    step "APPLY WISSKI STARTER RECIPE."
    drush recipe ../recipes/wisski_starter
    ok "WISSKI STARTER RECIPE APPLIED."
  else
    ok "WISSKI STARTER RECIPE SKIPPED."
  fi
  if [ -n "${WISSKI_DEFAULT_DATA_MODEL_VERSION}" ]; then
    install_default_data_model
  else
    ok "WISSKI DEFAULT DATA MODEL RECIPE SKIPPED."
  fi

  # After the recipes, when IMCE may be installed.
  set_imce_profiles

  # The settings.docker.php include is already in place; the module is not.
  step "CONFIGURING REDIS INTEGRATION."
  drush en redis -y >/dev/null
  drush cr >/dev/null
  ok "REDIS INTEGRATION CONFIGURED."

  step "SET SECURE PERMISSIONS."
  bash /usr/local/bin/set-permissions.sh
  ok "SECURE PERMISSIONS SET."

  # Record the package set version the site was installed with.
  cat "${IMAGE_PACKAGES_VERSION_FILE}" > "${SITE_PACKAGES_VERSION_FILE}" 2>/dev/null || true

  # Mark the installation as complete so restarts skip the install logic.
  rm -f "${INSTALL_IN_PROGRESS_FILE}"
  touch "${INSTALL_COMPLETE_FILE}"

  echo -e "\033[0;32m+---------------------------+\033[0m"
  echo -e "\033[0;32m|FINISHED INSTALLING DRUPAL.|\033[0m"
  echo -e "\033[0;32m+---------------------------+\033[0m"
}

# --- Existing site -----------------------------------------------------------
# Run database updates when the image ships a newer package set than the one
# the site was installed or last updated with.
update_site_if_package_set_changed() {
  local imagePackagesVersion sitePackagesVersion
  imagePackagesVersion="$(cat "${IMAGE_PACKAGES_VERSION_FILE}" 2>/dev/null || echo "unknown")"
  sitePackagesVersion="$(cat "${SITE_PACKAGES_VERSION_FILE}" 2>/dev/null || echo "unknown")"
  if [ "${imagePackagesVersion}" != "${sitePackagesVersion}" ]; then
    step "PACKAGE SET CHANGED (${sitePackagesVersion} -> ${imagePackagesVersion}); RUNNING DATABASE UPDATES..."
    drush updatedb -y
    drush cr
    echo "${imagePackagesVersion}" > "${SITE_PACKAGES_VERSION_FILE}"
    ok "DATABASE UPDATES APPLIED."
  fi
}

# What every start of an installed site does: triplestore, generated
# settings, permissions.
refresh_installed_site() {
  ensure_default_triplestore || exit 1
  write_docker_settings
  bash /usr/local/bin/set-permissions.sh
}

boot_site() {
  step "CHECKING IF DRUPAL IS ALREADY INSTALLED."
  if [ -f "${INSTALL_COMPLETE_FILE}" ]; then
    ok "DRUPAL IS ALREADY INSTALLED."
    ensure_key_value_expire
    update_site_if_package_set_changed
    refresh_installed_site
  elif [ -f "${INSTALL_IN_PROGRESS_FILE}" ]; then
    err "A previous installation attempt did not finish."
    echo "The site may be half-configured. Wipe the volumes (database and ${INSTALL_IN_PROGRESS_FILE%/*}) to reinstall,"
    echo "or finish the configuration manually and create ${INSTALL_COMPLETE_FILE} (and remove ${INSTALL_IN_PROGRESS_FILE})."
    exit 1
  elif [ -f "${SETTINGS_FILE}" ]; then
    # Legacy installation created before marker files were introduced.
    ok "DRUPAL IS ALREADY INSTALLED (LEGACY INSTALLATION DETECTED; CREATING MARKER FILE)."
    touch "${INSTALL_COMPLETE_FILE}"
    refresh_installed_site
  else
    install_site
  fi
}

# Extra Composer packages live in web/sites/composer.local.json (sites volume)
# and are applied onto the image's codebase on every start.
apply_composer_extras() {
  step "APPLYING SITE COMPOSER PACKAGES..."
  if /usr/local/bin/apply-composer-local.sh; then
    ok "SITE COMPOSER PACKAGES APPLIED."
    # Packages Composer installed at boot come from zip archives (644/755).
    /usr/local/bin/group-writable.sh
  else
    err "Failed to apply web/sites/composer.local.json onto this image."
    echo "Fix the extra package constraints or wait for a compatible image, then recreate the container."
    exit 1
  fi
}

# --- Services ----------------------------------------------------------------
# NGINX_WORKER_PROCESSES and PHP_FPM_MAX_CHILDREN come from .env / Compose.
# Raising workers without DRUPAL_CPUS / DRUPAL_MEMORY still hits the cgroup limit.
apply_runtime_performance() {
  local workers="${NGINX_WORKER_PROCESSES:-2}"
  local children="${PHP_FPM_MAX_CHILDREN:-6}"

  case "${workers}" in
    auto|[1-9]|[1-9][0-9]) ;;
    *)
      warn "invalid NGINX_WORKER_PROCESSES=${workers}; using 2."
      workers=2
      ;;
  esac

  if ! [[ "${children}" =~ ^[1-9][0-9]*$ ]] || [ "${children}" -gt 64 ]; then
    warn "invalid PHP_FPM_MAX_CHILDREN=${children}; using 6."
    children=6
  fi

  sed -i "s/^worker_processes .*/worker_processes ${workers};/" /etc/nginx/nginx.conf

  local start=$((children / 3))
  [ "${start}" -lt 1 ] && start=1
  local maxSpare=$((children / 2))
  [ "${maxSpare}" -lt 1 ] && maxSpare=1
  local minSpare=1
  [ "${minSpare}" -gt "${maxSpare}" ] && minSpare="${maxSpare}"

  cat > /usr/local/etc/php-fpm.d/zzz-wisski-runtime.conf <<EOF
[www]
pm = dynamic
pm.max_children = ${children}
pm.start_servers = ${start}
pm.min_spare_servers = ${minSpare}
pm.max_spare_servers = ${maxSpare}
pm.max_requests = 500
request_terminate_timeout = 300
EOF

  ok "RUNTIME PERFORMANCE: nginx workers=${workers}, php-fpm max_children=${children}."
}

start_iipsrv() {
  step "Starting IIPImage server..."
  export VERBOSITY="1"
  export LOGFILE="/var/log/iipsrv.log"
  export MAX_IMAGE_CACHE_SIZE="10"
  export JPEG_QUALITY="90"
  export MAX_CVT="5000"
  export MEMCACHED_SERVERS="localhost"
  # WissKI manifests use IIIF Image API v2; iipsrv 1.3 defaults to v3.
  export IIIF_VERSION="2"
  local bindAddress="127.0.0.1"
  local bindPort="9100"
  su -s /bin/bash www-data -c "exec /fcgi-bin/iipsrv.fcgi --bind ${bindAddress}:${bindPort}" &
  ok "IIPImage server started on ${bindAddress}:${bindPort}."
}

shutdown_services() {
  step "SHUTTING DOWN SERVICES..."
  if [ -n "${nginxPid:-}" ] && kill -0 "${nginxPid}" 2>/dev/null; then
    nginx -s quit 2>/dev/null || kill -TERM "${nginxPid}" 2>/dev/null || true
  fi
  pkill -QUIT php-fpm 2>/dev/null || true
  pkill -TERM memcached 2>/dev/null || true
  pkill -TERM -f iipsrv.fcgi 2>/dev/null || true
  wait 2>/dev/null || true
  ok "SERVICES STOPPED."
  exit 0
}

# Nothing runs at this point (this is the container's first process), so the
# services are started without checking for running copies.
start_services() {
  trap shutdown_services TERM INT

  apply_runtime_performance

  step "Starting PHP-FPM..."
  php-fpm -D
  ok "PHP-FPM started."

  step "Starting memcached..."
  memcached -d -u memcache -l 127.0.0.1 -m 64
  ok "Memcached started on 127.0.0.1:11211."

  start_iipsrv

  # Run nginx in the foreground so SIGTERM can drain in-flight requests first.
  nginx -g "daemon off;" &
  nginxPid=$!
  wait "${nginxPid}"
}

main() {
  banner
  prepare_developer_user
  validate_environment
  prepare_volumes
  ensure_wisski_dev_clone
  ensure_wisski_scs_base_clone
  ensure_dev_group_write
  boot_site
  prepare_phpunit
  sync_salz_adapter_urls
  apply_composer_extras
  ensure_mirador_library
  start_services
}

main
