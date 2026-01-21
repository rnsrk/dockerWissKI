# Changelog

## [Unreleased]

### Fixed
- Fixed `example-env` to use pipe separators (`|`) for `DRUPAL_TRUSTED_HOST` patterns instead of comma-separated values, matching the expected format in wisski-base-image entrypoint.sh.

## 1.0.1
- corrected trusted host env
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

