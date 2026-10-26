# PHP 8.5 FPM. Drupal core and modules are installed from the packages
# manifest, so the official Drupal image is not used.
ARG PHP_BASE_IMAGE_TAG=8.5-fpm-bookworm

# -----------------------------------------------------------------------------
# Builder: compile PHP extensions and iipsrv; toolchain stays in this stage.
# -----------------------------------------------------------------------------
FROM php:${PHP_BASE_IMAGE_TAG} AS builder

ARG MODE=production
ARG IIPSRV_VERSION=iipsrv-1.3

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    git \
    libavif-dev \
    libfreetype6-dev \
    libicu-dev \
    libjpeg-dev \
    libmemcached-dev \
    libonig-dev \
    libpng-dev \
    libpq-dev \
    libtiff-dev \
    libtool \
    libwebp-dev \
    libzip-dev \
    unzip \
    wget; \
    rm -rf /var/lib/apt/lists/*

# Install apcu (enabled at runtime via config/php/zz-apcu.ini).
RUN set -eux; \
    pecl install apcu

# Configure and install GD extension with AVIF support.
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
    --with-avif \
    && docker-php-ext-install -j"$(nproc)" gd

# Drupal-required extensions (the official Drupal image would have shipped these).
# PostgreSQL only; this stack has no MySQL/MariaDB driver.
RUN docker-php-ext-install -j"$(nproc)" \
    pdo_pgsql \
    zip

# Install intl.
RUN set -eux; \
    docker-php-ext-configure intl \
    && docker-php-ext-install intl

# Upload progress.
RUN set -eux; \
    git clone https://github.com/php/pecl-php-uploadprogress/ /usr/src/php/ext/uploadprogress/; \
    docker-php-ext-configure uploadprogress; \
    docker-php-ext-install uploadprogress; \
    rm -rf /usr/src/php/ext/uploadprogress

# Redis.
RUN set -eux; \
    pecl install redis-6.3.0; \
    docker-php-ext-enable redis

# xdebug (development mode only).
RUN set -eux; \
    if [ "$MODE" = "development" ]; then \
    pecl install xdebug-3.5.3; \
    docker-php-ext-enable xdebug; \
    fi

# iipsrv 1.3: AVIF, WebP, and memcached support are detected at configure time.
# See https://iipimage.sourceforge.io/2025/05/iipsrv-1-3.
RUN set -eux; \
    git clone --depth 1 --branch "${IIPSRV_VERSION}" https://github.com/ruven/iipsrv.git; \
    cd iipsrv; \
    ./autogen.sh; \
    ./configure; \
    make; \
    make check; \
    install -d /fcgi-bin; \
    install -m 755 src/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi; \
    cd /; \
    rm -rf /iipsrv

# -----------------------------------------------------------------------------
# Runtime: lean image with runtime libraries and compiled artifacts only.
# -----------------------------------------------------------------------------
FROM php:${PHP_BASE_IMAGE_TAG}

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1

ARG MODE=production
# Production: semver manifest path (wisski_base/production/<version>) with lock file.
ARG WISSKI_PACKAGES_VERSION=4.3.0
# Development: major-line manifest path (wisski_base/development/<line>), no lock file.
ARG WISSKI_PACKAGES_LINE=4.x

# Runtime packages only (no autoconf, lib*-dev, or other build toolchain).
# iipsrv, Redis, and the triplestore run in separate processes/containers.
# Development images also get operator CLI helpers (rg, fd, jq, ssh, …) so
# docker exec / agent searches and git@ remotes work without "command not found";
# gettext provides msgfmt for checking WissKI .po translations.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    curl \
    postgresql-client \
    git \
    imagemagick \
    iproute2 \
    libaom3 \
    libavif15 \
    libdav1d6 \
    libfreetype6 \
    libicu72 \
    libjpeg62-turbo \
    libmemcached11 \
    libonig5 \
    libpng16-16 \
    libpq5 \
    libtiff6 \
    libvips-tools \
    libwebp7 \
    libwebpmux3 \
    libzip4 \
    memcached \
    netcat-openbsd \
    nginx \
    rsync \
    sendmail \
    tini \
    unzip \
    vim \
    wget; \
    if [ "$MODE" = "development" ]; then \
    apt-get install -y --no-install-recommends \
    bash-completion \
    ca-certificates \
    fd-find \
    file \
    gettext \
    gnupg \
    jq \
    less \
    openssh-client \
    procps \
    ripgrep \
    tree; \
    ln -sfn /usr/bin/fdfind /usr/local/bin/fd; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# Node 22 + cspell for WissKI lint.sh / quicklint.sh (development only).
# Matches the official WissKI Dockerfile (nodesource 22, global corepack + cspell).
# COREPACK_HOME is shared so `developer` reuses the Yarn baked at build time.
ENV COREPACK_HOME=/usr/local/share/corepack \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN set -eux; \
    if [ "$MODE" != "development" ]; then \
    exit 0; \
    fi; \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    npm install -g corepack cspell; \
    npm cache clean --force; \
    rm -rf /var/lib/apt/lists/*

# GitHub CLI (development only) from the official apt repository; Debian
# bookworm's gh package is too old for current GitHub APIs.
RUN set -eux; \
    if [ "$MODE" != "development" ]; then \
    exit 0; \
    fi; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*

# Compiled PHP extensions, their enablement snippets, and the iipsrv binary.
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/docker-php-ext-*.ini /usr/local/etc/php/conf.d/
COPY --from=builder /fcgi-bin/iipsrv.fcgi /fcgi-bin/iipsrv.fcgi

# Who owns what:
# - /opt/drupal (core, vendor, modules, libraries) belongs to root. PHP-FPM
#   (www-data) can read but not write it, and Composer runs as root. Nothing
#   chowns or chmods this tree afterwards: that would copy every file into a
#   new layer. Composer and git already create 644/755 files.
# - Development: the tree is group-writable with group www-data (setgid) so
#   `developer` (in www-data) can edit it. umask 002 covers git checkouts;
#   packages from zip archives keep their 644/755, so the RUN that creates
#   them ends with `find … ! -perm -g=w -exec chmod g+w`. That touches only the
#   files that need it, which keeps the change inside the layer that created
#   them. A separate chmod -R in a later RUN would copy the whole tree.
# - The writable state (sites, private-files, custom modules and themes) lives
#   on volumes owned by www-data; the entrypoint prepares them.

# Bake the Drupal codebase from the drupal_packages composer manifest.
# Extra site packages are re-applied at boot from composer.local.json.
RUN set -eux; \
    if [ "$MODE" = "development" ]; then \
    umask 002; \
    install -d -g www-data -m 2775 /opt/drupal; \
    else \
    install -d -m 755 /opt/drupal; \
    fi; \
    cd /opt/drupal; \
    packagesRepoBaseUrl="https://raw.githubusercontent.com/soda-collections-objects-data-literacy/drupal_packages/main/wisski_base"; \
    if [ "$MODE" = "development" ]; then \
    manifestBaseUrl="${packagesRepoBaseUrl}/development/${WISSKI_PACKAGES_LINE}"; \
    curl -fsSL "${manifestBaseUrl}/composer.json" -o composer.json; \
    composer update --no-dev --no-interaction --no-progress --optimize-autoloader; \
    packagesVersion="${WISSKI_PACKAGES_LINE}-$(md5sum vendor/composer/installed.json | cut -d' ' -f1)"; \
    else \
    manifestBaseUrl="${packagesRepoBaseUrl}/production/${WISSKI_PACKAGES_VERSION}"; \
    curl -fsSL "${manifestBaseUrl}/composer.json" -o composer.json; \
    curl -fsSL "${manifestBaseUrl}/composer.lock" -o composer.lock; \
    composer install --no-dev --no-interaction --no-progress --optimize-autoloader; \
    packagesVersion="${WISSKI_PACKAGES_VERSION}"; \
    fi; \
    composer clear-cache; \
    ln -sf /opt/drupal/vendor/bin/drush /usr/local/bin/drush; \
    # php + nginx both ship /var/www/html as a directory. ln -sfn TARGET DIR
    # then creates DIR/web instead of replacing DIR, so SETTINGS_FILE and
    # WORKDIR miss the Drupal root (SALZ/reverse-proxy sync become no-ops).
    rm -rf /var/www/html; \
    ln -s /opt/drupal/web /var/www/html; \
    echo "${packagesVersion}" > /opt/drupal/.wisski-packages-version; \
    cp composer.json .wisski-composer.json; \
    if [ -f composer.lock ]; then cp composer.lock .wisski-composer.lock; fi; \
    mkdir -p /opt/drupal/web/modules/custom /opt/drupal/web/themes/custom; \
    if [ "$MODE" = "development" ]; then \
    find /opt/drupal -xdev ! -type l ! -perm -g=w -not -path '*/node_modules/*' -exec chmod g+w {} +; \
    fi

# WissKI lint and test tools into site vendor, the same layout as the Drupal
# GitLab CI: the module's require-dev (phpcs, phpstan, parallel-lint, …), its
# suggested modules (test modules depend on drupal/action, linkit, …), plus
# drupal/core-dev at the installed core version. core-dev brings phpunit,
# phpstan-phpunit, behat/mink and prophecy-phpunit; without them PHPStan does
# not narrow PHPUnit asserts and reports differently than GitLab.
# misc/scripts/_dev.sh falls back to PATH when the clone has no vendor/, so it
# picks these up. A clone vendor/ is not needed (drupal/potx would pull a
# second drupal/core into it and PHPStan aborts with "Cannot redeclare t()").
ENV PATH="/opt/drupal/vendor/bin:${PATH}"
COPY config/drupal/lib/list-wisski-require-dev.php /tmp/list-wisski-require-dev.php
RUN set -eux; \
    if [ "$MODE" != "development" ]; then \
    rm -f /tmp/list-wisski-require-dev.php; \
    exit 0; \
    fi; \
    umask 002; \
    cd /opt/drupal; \
    php /tmp/list-wisski-require-dev.php web/modules/contrib/wisski/composer.json composer.json > /tmp/wisski-require-dev.txt; \
    coreVersion="$(composer show drupal/core --format=json | php -r 'echo json_decode(stream_get_contents(STDIN), true)["versions"][0] ?? "";')"; \
    test -n "${coreVersion}"; \
    set -- "drupal/core-dev:${coreVersion}"; \
    while IFS= read -r pkg || [ -n "$pkg" ]; do \
    [ -n "$pkg" ] || continue; \
    set -- "$@" "$pkg"; \
    done < /tmp/wisski-require-dev.txt; \
    composer require --dev --no-update --no-interaction --no-progress "$@"; \
    composer update --with-all-dependencies --no-interaction --no-progress; \
    cp composer.json .wisski-composer.json; \
    cp composer.lock .wisski-composer.lock; \
    rm -f /tmp/list-wisski-require-dev.php /tmp/wisski-require-dev.txt; \
    composer clear-cache; \
    find /opt/drupal -xdev ! -type l ! -perm -g=w -not -path '*/node_modules/*' -exec chmod g+w {} +

# WissKI JS lint tools (cspell, eslint, stylelint) into the module's
# node_modules/, where misc/scripts/_dev.sh calls them. Same Yarn (corepack)
# and --immutable lock check as the GitLab stylelint job.
RUN set -eux; \
    if [ "$MODE" != "development" ]; then \
    exit 0; \
    fi; \
    cd /opt/drupal/web/modules/contrib/wisski; \
    if [ ! -f package.json ]; then \
    echo "WissKI has no package.json; skipping yarn install."; \
    exit 0; \
    fi; \
    umask 002; \
    install -d -g www-data -m 2775 "${COREPACK_HOME}"; \
    corepack enable; \
    yarn install --immutable; \
    rm -rf /root/.yarn /root/.cache

# JS libraries for WissKI and DLF AIM 3D Viewer (mirrors drush download commands).
# GitHub archive downloads fail intermittently on shared CI runners; retry.
# The 3D viewer ships three builds of the viewer (dev, prod, test) that nothing
# references; the Drupal module only loads dist/drupal/main.
# Mirador 4 (ProjectMirador/mirador) comes from the npm tarball: the git
# archive has no dist/, and the tarball unpacks into package/. The Mirador
# block loads libraries/mirador. The annotation editor is part of
# wisski-mirador-integration, so it is not installed on its own.
# That release is pinned in the installed module (MiradorLibrary.php). Baking
# it here lets an image start offline; the entrypoint downloads only when a
# clone pins a newer version. Older WissKI builds have no pin and skip this.
RUN set -eux; \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors "https://registry.npmjs.org/mirador/-/mirador-4.3.0.tgz" -o /tmp/mirador.tgz; \
    mkdir -p /opt/drupal/web/libraries/mirador /tmp/mirador-extract; \
    tar -xzf /tmp/mirador.tgz -C /tmp/mirador-extract; \
    cp -a --no-preserve=ownership /tmp/mirador-extract/package/. /opt/drupal/web/libraries/mirador/; \
    rm -rf /tmp/mirador.tgz /tmp/mirador-extract; \
    miradorLibrary="/opt/drupal/web/modules/contrib/wisski/wisski_mirador/src/MiradorLibrary.php"; \
    if [ -f "${miradorLibrary}" ]; then \
      miradorVersion="$(grep -E "const VERSION = '" "${miradorLibrary}" | head -n1 | cut -d "'" -f2)"; \
      miradorSha="$(grep -E "const ARCHIVE_SHA256 = '" "${miradorLibrary}" | head -n1 | cut -d "'" -f2)"; \
      test -n "${miradorVersion}"; \
      test -n "${miradorSha}"; \
      curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
        "https://github.com/rnsrk/wisski-mirador-integration/archive/refs/tags/v${miradorVersion}.zip" \
        -o /tmp/wisski-mirador-integration.zip; \
      echo "${miradorSha}  /tmp/wisski-mirador-integration.zip" | sha256sum -c -; \
      unzip -qo /tmp/wisski-mirador-integration.zip -d /tmp; \
      mkdir -p /opt/drupal/web/libraries/wisski-mirador-integration; \
      cp -a --no-preserve=ownership "/tmp/wisski-mirador-integration-${miradorVersion}/." /opt/drupal/web/libraries/wisski-mirador-integration/; \
      rm -f /opt/drupal/web/libraries/wisski-mirador-integration/*.map; \
      rm -rf /tmp/wisski-mirador-integration.zip "/tmp/wisski-mirador-integration-${miradorVersion}"; \
    fi; \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors "https://github.com/TurbojetTechnologies/colorbox/archive/1.7.0.zip" -o /tmp/colorbox.zip; \
    mkdir -p /opt/drupal/web/libraries/colorbox; \
    unzip -qo /tmp/colorbox.zip -d /tmp; \
    cp -a --no-preserve=ownership /tmp/colorbox-1.7.0/. /opt/drupal/web/libraries/colorbox/; \
    rm -rf /tmp/colorbox.zip /tmp/colorbox-1.7.0; \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors "https://github.com/cure53/DOMPurify/archive/main.zip" -o /tmp/dompurify.zip; \
    mkdir -p /opt/drupal/web/libraries/dompurify; \
    unzip -qo /tmp/dompurify.zip -d /tmp; \
    cp -a --no-preserve=ownership /tmp/DOMPurify-main/dist /opt/drupal/web/libraries/dompurify/; \
    rm -rf /tmp/dompurify.zip /tmp/DOMPurify-main; \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors "https://github.com/thedworak/dfg_3dviewer/archive/refs/heads/main.zip" -o /tmp/dlf_aim_3d_viewer.zip; \
    mkdir -p /opt/drupal/web/libraries/dlf_aim_3d_viewer; \
    unzip -qo /tmp/dlf_aim_3d_viewer.zip -d /tmp; \
    cp -a --no-preserve=ownership /tmp/dfg_3dviewer-main/. /opt/drupal/web/libraries/dlf_aim_3d_viewer/; \
    rm -rf /opt/drupal/web/libraries/dlf_aim_3d_viewer/dist/dev \
           /opt/drupal/web/libraries/dlf_aim_3d_viewer/dist/prod \
           /opt/drupal/web/libraries/dlf_aim_3d_viewer/dist/test; \
    rm -rf /tmp/dlf_aim_3d_viewer.zip /tmp/dfg_3dviewer-main; \
    if [ "$MODE" = "development" ]; then \
    find /opt/drupal -xdev ! -type l ! -perm -g=w -not -path '*/node_modules/*' -exec chmod g+w {} +; \
    fi

# Development also creates `developer` (host UID, in www-data) so an attached
# IDE can git/edit under /opt/drupal without root or sudo. PID 1 stays root
# (nginx, php-fpm). PHP-FPM workers stay www-data. The tree is already
# group-writable (see above); the user only has to be in the group.
# www-data is in the `developer` group in turn: functional tests run as
# `developer` and create sites/simpletest/<id> as developer:developer 775
# (Drupal's chmod drops setgid), and PHP-FPM has to write into it.
ARG DEV_UID=1000
ARG DEV_GID=1000
RUN set -eux; \
    if [ "$MODE" != "development" ]; then \
    exit 0; \
    fi; \
    groupadd --gid "${DEV_GID}" developer; \
    useradd --uid "${DEV_UID}" --gid developer --groups www-data \
      --create-home --home-dir /home/developer --shell /bin/bash developer; \
    usermod -aG developer www-data; \
    printf '%s\n' \
      'Host git.drupalcode.org' \
      '  Hostname git.drupal.org' \
      '  User git' \
      > /etc/ssh/ssh_config.d/drupal.conf; \
    git config --system --add url."git@git.drupal.org:".insteadOf "https://git.drupalcode.org/"; \
    git config --system --add url."git@git.drupal.org:".insteadOf "git@git.drupalcode.org:"

# Directories PHP-FPM, iipsrv and Composer write to.
# - /opt/drupal/private-files: persistent private files (mounted as a volume).
# - /var/tmp/drupal: PHP-FPM only (sys_temp_dir / pool env[TMPDIR]). Do not set
#   image ENV TMPDIR: Cursor's git askpass IPC socket uses os.tmpdir(), and a
#   global TMPDIR makes git push look for a missing vscode-git-*.sock there.
# - /var/composer-home: Composer home and cache (mounted as a volume). Group
#   www-data and setgid so `docker exec -u www-data` and `developer` can use it.
# - /var/log/iipsrv.log, and in development /var/log/xdebug: written by
#   www-data (iipsrv, PHP-FPM).
RUN set -eux; \
    install -d -o www-data -g www-data -m 775 /opt/drupal/private-files /var/tmp/drupal; \
    install -d -g www-data -m 2775 /var/composer-home /var/composer-home/cache /var/composer-home/cache/vcs /var/composer-home/cache/repo; \
    install -o www-data -g www-data -m 664 /dev/null /var/log/iipsrv.log; \
    if [ "$MODE" = "development" ]; then \
    install -d -o www-data -g www-data -m 775 /var/log/xdebug; \
    install -o www-data -g www-data -m 664 /dev/null /var/log/xdebug/xdebug.log; \
    fi; \
    mkdir -p /run/php /var/configs; \
    usermod -s /bin/bash www-data
ENV COMPOSER_HOME=/var/composer-home

# Disable Git "dubious ownership" checks inside the container.
RUN git config --system --add safe.directory '*'

# PHP configuration. The shared files go to every image, the OPcache and
# Xdebug settings come from config/php/<MODE>/. Each file only sets directives
# that no other file sets. Copied after the Composer layers so changing a
# setting does not rebuild the codebase.
COPY config/php/*.ini /usr/local/etc/php/conf.d/
COPY config/php/${MODE}/ /usr/local/etc/php/conf.d/

# php:*-fpm sets listen = 9000 in docker.conf; this later [www] file overrides
# it so nginx can use unix:/run/php/php-fpm.sock.
COPY config/php-fpm/zz-wisski-listen.conf /usr/local/etc/php-fpm.d/zz-wisski-listen.conf

# Nginx. The access and error log go to the container log in development.
COPY config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY config/nginx/drupal.conf /etc/nginx/conf.d/drupal.conf
COPY config/iipsrv/iipsrv.nginx.conf /etc/nginx/snippets/iipsrv.conf
RUN set -eux; \
    rm -f /etc/nginx/conf.d/default.conf; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    mkdir -p /run/nginx; \
    if [ "$MODE" = "production" ]; then \
    sed -i 's|access_log /var/log/nginx/access.log main;|access_log off;|' /etc/nginx/nginx.conf; \
    sed -i 's|error_log /var/log/nginx/error.log warn;|error_log off;|' /etc/nginx/nginx.conf; \
    fi

# Boot scripts, the Redis settings include (settings.docker.php includes it),
# and the login-shell PATH.
COPY config/redis/redis.settings.php /var/configs/redis.settings.php
COPY config/drupal/wisski-path.sh /etc/profile.d/wisski-path.sh
COPY --chmod=755 config/drupal/set-permissions.sh /usr/local/bin/set-permissions.sh
COPY --chmod=755 config/drupal/apply-composer-local.sh /usr/local/bin/apply-composer-local.sh
COPY --chmod=755 config/drupal/wisski-composer.sh /usr/local/bin/wisski-composer
COPY --chmod=755 config/drupal/group-writable.sh /usr/local/bin/group-writable.sh
COPY config/drupal/lib/sync-composer-local.php /usr/local/lib/wisski/sync-composer-local.php
COPY --chmod=755 entrypoint.sh /entrypoint.sh

LABEL org.wisski.packages.version="${WISSKI_PACKAGES_VERSION}" \
    org.wisski.packages.line="${WISSKI_PACKAGES_LINE}"

EXPOSE 80

STOPSIGNAL SIGTERM

# Health check via the health_check module endpoint. Compose uses this one.
# Long start period: the first boot installs and configures the whole site.
HEALTHCHECK --interval=15s --timeout=5s --start-period=30m --retries=30 \
    CMD curl -fsS http://localhost/health || exit 1

# Use tini as PID 1 for signal forwarding and zombie reaping. The entrypoint
# starts nginx, PHP-FPM, memcached, and iipsrv itself and ignores arguments.
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
