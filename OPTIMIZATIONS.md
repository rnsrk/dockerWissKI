# WissKI Performance Tuned Environment - Optimizations

This document describes all performance optimizations implemented in the tuned Drupal 11 WissKI environment, based on Drupal best practices and modern web performance standards.

## Quick Summary: What's Different?

This "tuned" environment differs from the "slow" environment by adding **three layers of caching** and **optimized database/PHP settings**:

| Component | Slow (Default) | Tuned | Speed Improvement |
|-----------|---------------|-------|-------------------|
| **Varnish** | ❌ Not present | ✅ Full-page cache | **10-100x faster** for anonymous users |
| **Redis** | ❌ Not present | ✅ Object cache + sessions | **50-100x faster** cache reads |
| **PHP OPcache** | 128MB (basic) | 512MB + JIT | **40-60% faster** code execution |
| **MariaDB Buffer** | 128MB | 1GB | **3-5x faster** queries |
| **Apache** | Basic config | Compression + caching headers | **70-80%** smaller files |

**Expected Real-World Impact:**
- **Anonymous user page load:** 2000ms → 50ms (40x faster)
- **Authenticated user page load:** 2000ms → 400ms (5x faster)
- **Concurrent users supported:** ~50 → 500+ (10x more)
- **Memory usage:** ~4GB → ~10GB (trade-off)

## Table of Contents

1. [PHP Optimizations](#php-optimizations)
2. [Apache Optimizations](#apache-optimizations)
3. [MariaDB/MySQL Optimizations](#mariadbmysql-optimizations)
4. [Caching Strategy](#caching-strategy)
5. [Resource Limits](#resource-limits)
6. [Service Architecture](#service-architecture)
7. [Configuration Guide](#configuration-guide)

---

## PHP Optimizations

### OPcache Configuration

OPcache is PHP's built-in bytecode cache that significantly improves performance by storing precompiled script bytecode in shared memory.

**What Changed:**

| Setting | Default | Tuned | Why Changed |
|---------|---------|-------|-------------|
| `opcache.memory_consumption` | 128MB | **512MB** | Drupal has many files; 128MB fills quickly causing cache evictions |
| `opcache.interned_strings_buffer` | 8MB | **32MB** | Stores repeated strings (class names, etc.); more = less memory duplication |
| `opcache.max_accelerated_files` | 10000 | **30000** | Drupal + contrib modules = 15k+ files; default causes cache misses |
| `opcache.revalidate_freq` | 2s | **2s** | How often to check if files changed; balanced for dev/prod |
| `opcache.jit` | disabled | **tracing** | PHP 8.3 JIT compiler: compiles hot code paths to machine code |
| `opcache.jit_buffer_size` | 0 | **128MB** | Memory for JIT compiled code; enables ~10-30% speedup |
| `opcache.huge_code_pages` | 0 | **1** | Uses OS huge pages for cache; reduces TLB misses |

**What's Happening:**
When PHP runs a `.php` file, it normally:
1. Reads file from disk
2. Parses PHP code into tokens
3. Compiles tokens into opcodes (bytecode)
4. Executes opcodes

OPcache stores step 3 (opcodes) in shared memory, so subsequent requests skip steps 1-3. With JIT enabled, frequently-executed opcodes are further compiled to native machine code for even faster execution.

**Impact:** First page load: same speed. All subsequent loads: **40-60% faster** because we skip parsing/compilation.

### APCu Configuration

APCu provides user cache for storing application data in shared memory (separate from OPcache which only caches compiled code).

**What Changed:**

| Setting | Default | Tuned | Why Changed |
|---------|---------|-------|-------------|
| `apc.shm_size` | 32MB | **256MB** | Drupal stores render cache, config here; 32MB exhausts quickly |
| `apc.ttl` | 0 (never) | **7200s** (2hrs) | Auto-expire old entries; prevents memory bloat |
| `apc.gc_ttl` | 3600s | **3600s** | Cleanup interval for expired entries |
| `apc.entries_hint` | 1000 | **4096** | Pre-allocate hash table size; reduces rehashing overhead |

**What's Happening:**
APCu is like Redis but lives in PHP's memory space. Drupal uses it to cache:
- Rendered HTML blocks (so they don't re-render every request)
- Computed values (expensive calculations)
- Configuration data

Unlike Redis (external process), APCu is per-PHP-process memory, so each Apache worker has its own cache. This is faster for access but doesn't share between workers.

**Impact:** Reduces database queries by **30-50%** for frequently accessed data.

### Redis Extension

Redis PHP extension enabled for object caching and session storage.

**What Changed:**

| Setting | Default | Tuned | Why Changed |
|---------|---------|-------|-------------|
| Extension | not installed | **installed** | Enables PHP to talk to Redis |
| `redis.session.locking_enabled` | 0 | **1** | Prevents two requests from corrupting same session |
| `redis.session.lock_retries` | -1 | **-1** | Keep trying to get lock (don't give up) |
| `redis.session.lock_wait_time` | 2000ms | **10000ms** | Wait up to 10s for lock (for slow operations) |

**What's Happening:**
Redis is an external key-value store (like a super-fast database in memory). Unlike APCu which is per-PHP-process:
- **Shared:** All Apache workers see the same Redis cache
- **Persistent:** Survives PHP restarts
- **Distributed:** Can share cache across multiple servers (if scaled)

Session locking prevents this race condition:
```
Request 1: Read session → Modify cart → Write session (takes 2 seconds)
Request 2: Read session (at 1 second) → Modify cart → Write session
Result without locking: Request 2 overwrites Request 1's changes! Cart corrupted.
Result with locking: Request 2 waits for Request 1 to finish, then proceeds safely.
```

**Impact:** Centralized cache means **consistent data** across all workers, better for authenticated users.

### Memory and Execution Settings

- `memory_limit=1G` - Adequate for WissKI operations
- `max_execution_time=300` - 5 minutes for long operations
- `output_buffering=on` - Reduce HTTP overhead

---

## Apache Optimizations

### Performance Modules Enabled

1. **mod_deflate** - Gzip compression for text-based content
2. **mod_expires** - Browser caching headers
3. **mod_headers** - Custom HTTP headers
4. **mod_http2** - HTTP/2 protocol support
5. **mod_brotli** - Brotli compression (more efficient than gzip)

### Compression Configuration

**Compressed Content Types:**
- HTML, CSS, JavaScript
- XML, JSON, RSS
- SVG images

**Benefits:**
- 70-80% reduction in transfer size
- Faster page loads
- Reduced bandwidth usage

### Browser Caching

**Cache Expiration Times:**
- Static assets (images, fonts): 1 year
- CSS/JavaScript: 1 year
- HTML: No cache (dynamic content)

**Benefits:**
- Faster subsequent page loads
- Reduced server load
- Better user experience for returning visitors

### Keep-Alive Settings

```apache
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
```

**Benefits:**
- Reuse TCP connections
- Reduce connection overhead
- Faster page rendering

### Security Headers

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `X-XSS-Protection: 1; mode=block`

---

## MariaDB/MySQL Optimizations

### InnoDB Configuration

**What Changed:**

| Setting | Default | Tuned | Why Changed |
|---------|---------|-------|-------------|
| `innodb-buffer-pool-size` | 128MB | **1GB** | Caches table data in RAM; default fits ~1000 rows, ours fits ~1M rows |
| `innodb-log-file-size` | 48MB | **256MB** | Transaction log; larger = fewer disk flushes, faster writes |
| `innodb-flush-log-at-trx-commit` | 1 | **2** | `1`=sync every commit (slow, safe), `2`=sync every second (fast, 99.9% safe) |
| `innodb-flush-method` | fsync | **O_DIRECT** | Bypass OS file cache (avoid double-caching) |
| `innodb-file-per-table` | 1 | **1** | One file per table (easier management, already default) |
| `max-connections` | 151 | **200** | More concurrent users allowed |
| `table-open-cache` | 4000 | **4000** | Keep more tables open (reduce file open/close) |
| `query-cache-size` | 0 | **64MB** | Cache frequent SELECT queries |
| `tmp-table-size` | 16MB | **64MB** | Larger temp tables stay in RAM (not disk) |

**What's Happening:**

**Buffer Pool (Most Important):**
Think of it as MariaDB's "RAM disk". When you query a table:
1. Check buffer pool first (if data is there → instant response)
2. If not in buffer pool → read from disk (slow) → store in buffer pool for next time

Default 128MB = can cache ~5-10 typical Drupal tables. With 1GB = cache all tables + indexes = **99% of queries never touch disk**.

**Flush Log at Commit:**
- `1` (default): Every INSERT/UPDATE waits for disk write. Safe if power fails, but **SLOW**.
- `2` (tuned): Writes to RAM log immediately (fast), syncs to disk every second. If power fails within that 1 second, you lose ~1 second of data. **99.9% safe, 3-5x faster**.

**O_DIRECT Flush:**
By default, writes go: MariaDB → OS cache → disk (double buffering, wasteful).
With O_DIRECT: MariaDB → disk directly (MariaDB's buffer pool is better than OS cache).

**Impact:** Database queries are **3-5x faster** because data is cached in RAM, not read from disk every time.

### Connection Management

- `max-connections=200` - Increased connection pool
- `thread-cache-size=50` - Reuse threads for new connections

**Benefits:**
- Handle more concurrent users
- Reduced connection overhead

### Query Cache

- `query-cache-type=1` - Enable query cache
- `query-cache-size=64M` - Cache size
- `query-cache-limit=2M` - Max result size to cache

**Note:** Query cache is deprecated in MySQL 8.0+, but still useful in MariaDB 11.5.

### Table and Buffer Optimization

- `table-open-cache=4000` - Keep more tables open
- `tmp-table-size=64M` - Temporary table size in memory
- `max-heap-table-size=64M` - Max MEMORY table size
- `join-buffer-size=4M` - Buffer for full table joins
- `sort-buffer-size=4M` - Buffer for sorting operations
- `read-rnd-buffer-size=2M` - Buffer for reading rows in sorted order

**Benefits:**
- Faster complex queries
- Better handling of large datasets
- Reduced disk I/O

---

## Caching Strategy

### Three-Layer Caching Architecture

```
User → Varnish → Drupal/Apache → PHP/OPcache → MariaDB
              ↓
            Redis
```

### Layer 1: Varnish (HTTP Cache)

**Purpose:** Full-page caching for anonymous users

**What Changed:**

| Aspect | Without Varnish | With Varnish | Why |
|--------|----------------|--------------|-----|
| Anonymous page load | Every request hits PHP/Drupal | First request hits PHP, rest from cache | Skip entire PHP/Drupal stack |
| Memory | 0 | **256MB** | Stores rendered HTML pages |
| Cache strategy | None | **Smart VCL rules** | Knows what to cache, what to skip |

**What's Happening:**

Varnish sits **in front of Apache**:
```
Without Varnish:  User → Apache → PHP → Drupal → Database → render HTML → send
With Varnish:     User → Varnish (cache hit) → send cached HTML (done!)
                  User → Varnish (cache miss) → Apache → PHP → etc.
```

**VCL Rules (Varnish Configuration Language):**
- **Cache:** Homepage, article pages, static files (for anonymous users)
- **Don't Cache:** Admin pages (`/admin/*`), user pages (`/user/*`), AJAX, POST requests, logged-in users (cookies)
- **Smart:** Strips tracking cookies (Google Analytics, etc.) so they don't prevent caching

**Grace Period:**
If Drupal crashes, Varnish serves stale (old) cached pages for 6 hours rather than showing errors. Your site stays up even if backend is down!

**Impact:** Cached pages load in **20-50ms** instead of 500-2000ms. That's **10-100x faster**. Can handle 1000s of concurrent anonymous users on small hardware.

### Layer 2: Redis (Object Cache)

**Purpose:** Application-level caching and session storage

**What Changed:**

| Setting | Without Redis | With Redis | Why |
|---------|--------------|------------|-----|
| Cache backend | Database tables | **Redis in-memory** | 50-100x faster than SQL |
| Memory | 0 | **512MB** | Dedicated cache storage |
| Eviction | Manual cleanup | **allkeys-lru** | Auto-remove old entries |
| Persistence | N/A | **AOF** (sync every 60s) | Survive restarts |

**What's Happening:**

Redis stores Drupal's cache in memory instead of database tables:

```
Without Redis: Need to show a block?
  → Query cache table in MariaDB → Check if valid → Maybe query content tables → Render → Store in cache table

With Redis: Need to show a block?
  → GET "cache:render:block:123" from Redis → Return (microseconds)
```

**LRU Eviction:**
When Redis fills up to 512MB:
- Identifies **Least Recently Used** keys
- Removes them automatically
- Keeps frequently-accessed data in cache

**AOF Persistence:**
- Every write is logged to disk (append-only file)
- If server crashes, Redis replays log on startup
- Balances performance (not syncing every write) with safety (sync every 60s or 1000 changes)

**Use Cases in Drupal:**
- `cache.render`: Rendered blocks, menu HTML
- `cache.data`: Entity lists, computed values
- `cache.discovery`: Plugin definitions, routing
- Sessions: User login state, shopping carts

**Impact:** Cache reads are **50-100x faster** than database. Reduces database load by **60-80%**.

### Layer 3: PHP OPcache & APCu

**Purpose:** PHP bytecode and application data caching

**Benefits:**
- No disk I/O for PHP scripts
- Persistent application cache
- Fastest cache layer (in-process memory)

---

## Resource Limits

Resource limits ensure fair resource allocation and prevent any single service from consuming all system resources.

### Drupal Container

```yaml
limits:
  cpus: '2.0'
  memory: 2G
reservations:
  cpus: '0.5'
  memory: 512M
```

**Reasoning:** Main application server, needs adequate resources for PHP processing.

### MariaDB Container

```yaml
limits:
  cpus: '2.0'
  memory: 2G
reservations:
  cpus: '0.5'
  memory: 1G
```

**Reasoning:** Database is CPU and memory intensive, especially with InnoDB buffer pool.

### RDF4J Container

```yaml
limits:
  cpus: '2.0'
  memory: 5G
reservations:
  cpus: '0.5'
  memory: 1G
```

**Reasoning:** Triplestore requires significant memory for Java heap (4GB configured).

### Solr Container

```yaml
limits:
  cpus: '1.0'
  memory: 1536M
reservations:
  cpus: '0.25'
  memory: 512M
```

**Reasoning:** Search indexing is memory-intensive but doesn't need constant high CPU.

### Redis Container

```yaml
limits:
  cpus: '1.0'
  memory: 768M
reservations:
  cpus: '0.25'
  memory: 256M
```

**Reasoning:** Fast in-memory cache, lightweight but needs memory buffer.

### Varnish Container

```yaml
limits:
  cpus: '1.0'
  memory: 512M
reservations:
  cpus: '0.25'
  memory: 256M
```

**Reasoning:** Reverse proxy cache, minimal resource requirements.

---

## Service Architecture

### Service Dependencies

```
Drupal depends on:
  - MariaDB (database)
  - Redis (caching)

Varnish depends on:
  - Drupal (backend)
```

### Healthchecks

All critical services include healthchecks:

- **Drupal:** HTTP request to `/`
- **MariaDB:** InnoDB initialization check
- **Redis:** PING command
- **RDF4J:** Protocol endpoint check
- **Varnish:** varnishstat command

**Benefits:**
- Automatic service recovery
- Graceful startup orchestration
- Container restart on failure

### Network Ports

| Service | Default Port | Environment Variable |
|---------|-------------|---------------------|
| Drupal (HTTP) | 3000 | `DRUPAL_PORT` |
| Drupal (via Varnish) | 3005 | `VARNISH_PORT` |
| MariaDB | 3306 | `DB_PORT` (not exposed by default) |
| RDF4J | 3002 | `RDF4J_PORT` |
| Solr | 3003 | `SOLR_PORT` |
| Redis | 3004 | `REDIS_PORT` |
| Adminer | 3001 | `ADMINER_PORT` |

---

## Configuration Guide

### Initial Setup

1. Copy the example environment file:
```bash
cp example-env .env
```

2. Edit `.env` and configure your settings:
```bash
DRUPAL_DOMAIN=your-domain.com
DRUPAL_USER=admin
DRUPAL_PASSWORD=secure-password
SITE_NAME=My WissKI Site
```

3. Build and start the services:
```bash
docker-compose up -d --build
```

### Accessing the Site

- **Through Varnish (recommended):** `http://localhost:3005`
- **Direct to Drupal:** `http://localhost:3000`
- **Adminer (Database UI):** `http://localhost:3001`
- **Solr Admin:** `http://localhost:3003`
- **RDF4J Workbench:** `http://localhost:3002`

### Enabling Redis in Drupal

**Automatic Configuration:**
Redis is automatically configured during container startup! The entrypoint script will:
1. Install the Drupal Redis module via Composer
2. Add Redis configuration to `settings.php`
3. Enable the Redis module via Drush

This happens automatically 30 seconds after the container starts, allowing Drupal installation to complete first.

**Manual Configuration (if needed):**
If you need to manually configure Redis, add to `settings.php`:

```php
$settings['redis.connection']['interface'] = 'PhpRedis';
$settings['redis.connection']['host'] = 'redis';
$settings['redis.connection']['port'] = 6379;
$settings['cache']['default'] = 'cache.backend.redis';
```

**Verify Redis is Working:**
```bash
# Check if Redis module is enabled
docker exec wisski-performance-tuned-drupal drush pm:list --status=enabled | grep redis

# Check cache backends
docker exec wisski-performance-tuned-drupal drush eval "print_r(\Drupal::service('cache.backend.redis'));"
```

### Monitoring Performance

**Check Varnish Cache Hits:**
```bash
docker exec wisski-performance-tuned-varnish varnishstat
```

**Check Redis Memory Usage:**
```bash
docker exec wisski-performance-tuned-redis redis-cli info memory
```

**Check OPcache Status:**
Create a PHP file with:
```php
<?php phpinfo(); ?>
```
Look for OPcache statistics.

**Check MariaDB Performance:**
```bash
docker exec wisski-performance-tuned-mariadb mysql -u root -p -e "SHOW STATUS LIKE 'Innodb_buffer_pool%';"
```

### Tuning for Your Environment

#### Low Memory Systems (< 8GB RAM)

Reduce memory allocations:
- MariaDB: `innodb-buffer-pool-size=512M`
- RDF4J: `JAVA_OPTS=-Xms512m -Xmx2g`
- PHP: `opcache.memory_consumption=256`
- Redis: `maxmemory 256mb`

#### High Memory Systems (> 16GB RAM)

Increase memory allocations:
- MariaDB: `innodb-buffer-pool-size=4G`
- RDF4J: `JAVA_OPTS=-Xms2g -Xmx8g`
- PHP: `opcache.memory_consumption=1024`
- Redis: `maxmemory 2gb`
- Varnish: `VARNISH_SIZE=1G`

---

## Performance Benchmarks

Expected performance improvements over the "slow" configuration:

| Metric | Slow | Tuned | Improvement |
|--------|------|-------|-------------|
| Time to First Byte (TTFB) | ~500ms | ~50-100ms | **80-90% faster** |
| Full Page Load (anonymous) | ~2000ms | ~200-400ms | **80-90% faster** |
| Full Page Load (cached) | ~2000ms | ~20-50ms | **95-98% faster** |
| Database Query Time | ~100ms | ~20-30ms | **70-80% faster** |
| Concurrent Users Supported | ~50 | ~500+ | **10x improvement** |
| Memory Usage (total) | ~4GB | ~8-10GB | Trade-off for performance |

**Note:** Actual results depend on hardware, network, and content complexity.

---

## Troubleshooting

### Varnish Not Caching

- Check `X-Varnish-Cache` header
- Ensure you're not logged in (cookies bypass cache)
- Verify VCL configuration is loaded

### Redis Connection Errors

- Check Redis is running: `docker ps | grep redis`
- Verify connection from Drupal: `docker exec wisski-performance-tuned-drupal redis-cli -h redis ping`

### High Memory Usage

- Check container stats: `docker stats`
- Reduce resource limits if needed
- Consider upgrading hardware

### Slow Queries

- Enable MariaDB slow query log
- Use Drupal's Database Logging
- Optimize indexes on frequently queried tables

---

## Security Considerations

1. **Varnish Cache Poisoning:** Ensure proper cookie handling in VCL
2. **Redis Security:** Redis is not exposed externally by default
3. **Database Access:** MariaDB port is not exposed by default
4. **Apache Security Headers:** Already configured
5. **Regular Updates:** Keep all services updated

---

## Maintenance Tasks

### Daily
- Monitor disk space
- Check error logs

### Weekly
- Review slow query logs
- Clear old Varnish cache if needed
- Check Redis memory usage

### Monthly
- Update Docker images
- Optimize MariaDB tables: `OPTIMIZE TABLE`
- Backup databases and volumes

### Quarterly
- Review and adjust resource limits
- Performance benchmarking
- Security audit

---

## Additional Resources

- [Drupal Performance Best Practices](https://www.drupal.org/docs/administering-a-drupal-site/managing-site-performance)
- [Varnish Cache Documentation](https://varnish-cache.org/docs/)
- [Redis Best Practices](https://redis.io/docs/manual/patterns/)
- [MariaDB Performance Tuning](https://mariadb.com/kb/en/optimization-and-tuning/)
- [PHP OPcache Configuration](https://www.php.net/manual/en/opcache.configuration.php)

---

## Version Information

- **Drupal:** 11.2.4
- **PHP:** 8.3
- **MariaDB:** 11.5
- **Redis:** 7.4
- **Varnish:** 7.6
- **Solr:** 9.7
- **Apache:** 2.4 (from Drupal image)

---

## Credits

Optimizations based on:
- [Drupal.org Performance Documentation](https://www.drupal.org/docs/7/managing-site-performance-and-scalability/optimizing-drupal-to-load-faster-server-mysql-caching-theming-html)
- Drupal 11 best practices
- Modern web performance standards
- PHP 8.3 JIT compiler features

Last Updated: October 27, 2025

