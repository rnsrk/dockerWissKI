# Changelog

## [Unreleased]

### Added
- Optional `solr` Compose profile (off until a Search API core exists).
- OpenGDB RDF4J entrypoint (named-volume UID) and nginx template with a short Docker DNS TTL.
- pgAdmin `servers.json` filled from `DB_*` on every start.
- Development Drupal image CLI helpers (ripgrep, fd, jq, and related tools).
- `ENTRYPOINT_DEBUG` to trace the Drupal entrypoint without flooding Compose logs.

### Changed
- Drupal SPARQL talks to `authproxy:8000` (OpenGDB ACLs). First install creates the repository via `POST /rest/repositories`.
- WissKI packages pin `3.7.0`.
- Redis persistence is RDB only. PostgreSQL buffers are sized for typical laptop RAM.
- Production PHP-FPM pool is sized for the 2G Drupal cgroup.
- First install skips `drush locale-update` (run later if you need contrib translations).
- `.env.example` leaves passwords and emails empty.

### Fixed
- `composer.local.json` apply uses `--update-no-dev` so extras install onto a production lock.
- Drupal redirects keep the published host port (`absolute_redirect off` and `HTTP_HOST $http_host`).
- SALZ adapter read/write URLs are synced on every boot.

### Removed
- Leftover `test-performance.sh` from the old tuned stack.

## 3.0.0

### Breaking Changes
- Drupal image is built in this repository (`drupal/`) and published to `ghcr.io/rnsrk/dockerwisski-{production,development}`. The SODA `wisski-base-image` pull is gone.
- MariaDB is replaced by PostgreSQL 16 (`pg_trgm` required). Volume `mariadb-data` is not reused.
- The local RDF4J image is replaced by an [OpenGDB](https://github.com/FAU-CDI/open_gdb) git submodule (`git clone --recurse-submodules`).
- Only `web/sites` and `private-files` persist; the Drupal codebase is immutable in the image.
- Development and production are env presets (`env/development.env`, `env/production.env`). Varnish starts only with the `production` Compose profile. pgAdmin is the `tools` profile.
- Nextcloud, Keycloak/OIDC, Traefik, and Adminer wiring are removed. Database UI is pgAdmin.

### Added
- PHP-FPM + Nginx Drupal image sources, GitHub Actions GHCR publish (linux/amd64).
- Compose Specification layout: `include` for OpenGDB, `COMPOSE_FILE` in `.env`, committed `docker-compose.override.yml`.
- Site extras via persistent `composer.local.json` (re-applied onto each new image at boot), plus volumes for `web/modules/custom` and `web/themes/custom`.

## 2.0.1

### Added
- Apple Silicon (M1/M2/M3) workaround: `docker-compose.apple-silicon.yml` to run amd64 images via Rosetta emulation when "no matching manifest for linux/arm64/v8" occurs.

### Changed
- README: Added troubleshooting section for Apple Silicon and manifest errors.

## 2.0.0

### Breaking Changes
- **Environment variable renames** (update your `.env` when upgrading from 1.x):
  - `SITE_NAME` → `DRUPAL_SITE_NAME`
  - `DEFAULT_GRAPH` → `WISSKI_DEFAULT_GRAPH`
  - `DOMAIN` → `DRUPAL_DOMAIN`

### Fixed
- Fixed `example-env` to use pipe separators (`|`) for `DRUPAL_TRUSTED_HOSTS` patterns instead of comma-separated values, matching the expected format in wisski-base-image entrypoint.sh.

### Changed
- Renamed `SITE_NAME` to `DRUPAL_SITE_NAME`.
- Renamed `DEFAULT_GRAPH` to `WISSKI_DEFAULT_GRAPH`.
- Renamed `DOMAIN` to `DRUPAL_DOMAIN`.
- Updated default values for `WISSKI_DEFAULT_DATA_MODEL_VERSION` and `WISSKI_STARTER_VERSION` to `1.x-dev`.
- `TS_USERNAME` and `TS_PASSWORD` now have default values (`ts_user` / `ts_password`) instead of empty strings.
- Reorganized `example-env` and `docker-compose.yml` environment variables for consistency.

### Added
- `DRUPAL_PRIVATE_FILES_DIR` environment variable for private files directory.
- `DRUPAL_VERSION` for PHP/Drupal base image version.
- `WISSKI_BASE_IMAGE_VERSION` for WissKI base image version.
- `REDIS_HOST` in example-env.
- `TS_TOKEN` for RDF4J token authentication.
- `DRUPAL_LOCALE` in example-env.

## 1.0.1

### Fixed
- Corrected trusted host environment variable configuration.
## 1.0.0
### Performance Tuned Branch (vs main)

This changelog documents all changes between the `main` and `tuned` branches, focusing on performance optimizations and infrastructure improvements.

#### Added

##### New Files and Directories
- **drupal/Dockerfile** - Custom Dockerfile for Drupal container with performance optimizations
- **drupal/entrypoint.sh** - Enhanced entrypoint script with Redis configuration and performance tuning
- **drupal/redis.settings.php** - Redis cache backend configuration for Drupal
- **drupal/set-permissions.sh** - Script for setting secure file permissions following Drupal security guidelines
- **varnish/default.vcl** - Varnish configuration file with Drupal-optimized caching rules
- **test-performance.sh** - Performance testing script
- **OPTIMIZATIONS.md** - Documentation for performance optimizations
- **TESTING.md** - Testing documentation

##### Docker Compose Enhancements
- Added resource limits and reservations for all services:
  - **Drupal**: 2 CPUs limit, 2G memory limit, 0.5 CPU reservation, 512M memory reservation
  - **MariaDB**: 2 CPUs limit, 2G memory limit, 0.5 CPU reservation, 1G memory reservation
  - **Solr**: 1 CPU limit, 1536M memory limit, 0.25 CPU reservation, 512M memory reservation
  - **RDF4J**: 2 CPUs limit, 5G memory limit, 0.5 CPU reservation, 1G memory reservation
  - **Redis**: 1 CPU limit, 768M memory limit, 0.25 CPU reservation, 256M memory reservation
  - **Varnish**: 1 CPU limit, 512M memory limit, 0.25 CPU reservation, 256M memory reservation

#### Changed

##### MariaDB Performance Tuning (2025-10-27)
- **Transaction isolation**: Set to READ-COMMITTED for better performance
- **InnoDB buffer pool**: Increased to 1G
- **InnoDB log file size**: Set to 256M
- **InnoDB log buffer**: Set to 32M
- **InnoDB flush log**: Changed to flush every 2 transactions (performance mode)
- **I/O threads**: Configured 4 read and 4 write threads
- **I/O capacity**: Set to 1000 (max 2000)
- **Purge threads**: Increased to 2
- **Adaptive hash index**: Enabled
- **Connection limits**: Max 200 connections, 180 user connections
- **Table caches**: Increased table-open-cache to 4000, table-definition-cache to 2000
- **Thread cache**: Set to 50
- **Buffer sizes**: Optimized tmp-table-size, max-heap-table-size, join-buffer-size, sort-buffer-size
- **Read buffers**: Configured read-buffer-size (1M) and read-rnd-buffer-size (2M)
- **Binary logging**: Configured binlog-cache-size (1M) and max-binlog-size (256M)
- **Slow query logging**: Enabled with 2-second threshold
- **Character set**: UTF8MB4 with unicode_ci collation
- **Max allowed packet**: Increased to 64M
- **Timeouts**: Extended wait-timeout and interactive-timeout to 600 seconds

##### Redis Configuration Improvements (2025-10-27)
- Enhanced Redis settings in `drupal/redis.settings.php`
- Improved cache backend configuration for better performance
- Updated Redis connection settings in docker-compose.yml

##### Varnish Memory Optimization (2025-12-05)
- Increased Varnish memory allocation (commit: 68ec4bd, 965ecec)
- Optimized Varnish cache size configuration

##### Environment Variables
- Updated `WISSKI_STARTER_VERSION` environment variable handling (2025-10-27)
- Removed some unused environment variables (2025-12-05)
- Added Composer VCS repository configuration for WissKI (2025-11-25)

#### Performance Improvements

##### Overall System Performance
- **Resource allocation**: All services now have defined CPU and memory limits to prevent resource contention
- **Database optimization**: MariaDB tuned for high-performance Drupal workloads
- **Caching**: Redis integration with optimized configuration
- **Reverse proxy**: Varnish configured with Drupal-specific caching rules
- **Connection pooling**: Optimized database connection settings

##### Service-Specific Optimizations
- **Drupal**: Resource limits ensure consistent performance
- **MariaDB**: Extensive InnoDB and connection optimizations
- **Solr**: Memory allocation tuned for search performance
- **RDF4J**: Increased memory for large triple store operations
- **Redis**: Optimized for cache performance
- **Varnish**: Memory allocation increased for better cache hit rates

#### Technical Details

##### Files Changed
- `docker-compose.yml` - Added resource limits, MariaDB performance tuning, Varnish configuration
- `drupal/Dockerfile` - New custom Dockerfile (298 lines added)
- `drupal/entrypoint.sh` - New entrypoint script (421 lines added)
- `drupal/redis.settings.php` - Redis configuration (121 lines added)
- `drupal/set-permissions.sh` - Permission management script (151 lines added)
- `varnish/default.vcl` - Varnish configuration (145 lines added)
- `example-env` - Updated environment variable examples

#### Summary

The merge of the `tuned` branch represents a comprehensive performance optimization of the Docker WissKI stack, with:
- **1,136 lines** of new code added
- **5 new files** for performance optimization
- **Resource limits** configured for all 6 services
- **Database tuning** with 20+ MariaDB optimizations
- **Caching improvements** via Redis and Varnish
- **Production-ready** configuration for high-traffic Drupal/WissKI installations

