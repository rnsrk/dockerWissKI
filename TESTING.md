# Testing Guide - WissKI Performance Tuned Environment

This guide helps you verify that all performance optimizations are working correctly.

## Quick Health Check

```bash
cd /home/rnsrk/sites/wisski-dev/tuned

# Check all containers are running and healthy
docker compose ps

# Should show all services as "healthy" or "Up"
```

Expected output:
```
NAME                               STATUS
wisski-performance-tuned-adminer   Up
wisski-performance-tuned-drupal    Up (healthy)
wisski-performance-tuned-mariadb   Up (healthy)
wisski-performance-tuned-rdf4j     Up (healthy)
wisski-performance-tuned-redis     Up (healthy)
wisski-performance-tuned-solr      Up
wisski-performance-tuned-varnish   Up (healthy)
```

---

## 1. Test Varnish HTTP Cache

### Test 1: Check Varnish is Running

```bash
# Check Varnish responds
curl -I http://localhost:8000

# Look for these headers:
# X-Varnish-Cache: MISS (first request)
# Via: 1.1 varnish (... indicates Varnish is active)
```

### Test 2: Verify Caching Works

```bash
# First request (cache miss)
curl -I http://localhost:8000

# Second request (should be cache hit)
curl -I http://localhost:8000

# Look for: X-Varnish-Cache: HIT
```

**Expected Result:**
```
HTTP/1.1 302 Found
X-Varnish-Cache: HIT
Via: 1.1 varnish (Varnish/7.6)
Age: 5
```

### Test 3: Performance Comparison

```bash
# Time without Varnish (direct to Drupal)
time curl -s http://localhost:80 > /dev/null

# Time with Varnish (cached)
time curl -s http://localhost:8000 > /dev/null

# Varnish should be 10-100x faster
```

### Test 4: Cache Statistics

```bash
docker exec wisski-performance-tuned-varnish varnishstat -1

# Look for:
# MAIN.cache_hit         - Number of cache hits
# MAIN.cache_miss        - Number of cache misses
# Hit ratio = cache_hit / (cache_hit + cache_miss)
```

**Good cache hit ratio:** > 80%

---

## 2. Test Redis Object Cache

### Test 1: Check Redis Connection

```bash
# Ping Redis
docker exec wisski-performance-tuned-redis redis-cli ping

# Expected: PONG
```

### Test 2: Check Redis Module Status

```bash
# Check if Redis module is enabled in Drupal
docker exec wisski-performance-tuned-drupal drush pm:list --status=enabled | grep redis

# Expected: redis (Module) Enabled
```

### Test 3: Verify Cache Data in Redis

```bash
# Check Redis memory usage
docker exec wisski-performance-tuned-redis redis-cli INFO memory

# Look for:
# used_memory_human:50M (or similar - should be > 0)
```

### Test 4: Check Drupal Cache Bins

```bash
# List Redis keys (shows Drupal cache data)
docker exec wisski-performance-tuned-redis redis-cli KEYS "*cache*" | head -20

# Should show keys like:
# drupal:cache:bootstrap:...
# drupal:cache:render:...
# drupal:cache:data:...
```

### Test 5: Redis Performance Stats

```bash
# Get Redis statistics
docker exec wisski-performance-tuned-redis redis-cli INFO stats

# Look for:
# total_commands_processed - Should be growing
# keyspace_hits / keyspace_misses - Hit ratio should be high
```

**Good hit ratio:** > 90%

---

## 3. Test PHP OPcache

### Test 1: Check OPcache is Enabled

```bash
# Check OPcache status
docker exec wisski-performance-tuned-drupal php -i | grep opcache.enable

# Expected: opcache.enable => On => On
```

### Test 2: Check OPcache JIT

```bash
# Check JIT is enabled
docker exec wisski-performance-tuned-drupal php -i | grep opcache.jit

# Expected:
# opcache.jit => tracing => tracing
# opcache.jit_buffer_size => 128M => 128M
```

### Test 3: OPcache Statistics

```bash
# Create a PHP script to check OPcache stats
docker exec wisski-performance-tuned-drupal php -r "print_r(opcache_get_status());"

# Look for:
# [opcache_enabled] => 1
# [cache_full] => 0 (should not be full)
# [num_cached_scripts] => large number (thousands)
# [hits] >> [misses] (hit rate should be > 95%)
```

### Test 4: Check Memory Usage

```bash
# Check OPcache memory
docker exec wisski-performance-tuned-drupal php -r "
\$status = opcache_get_status();
echo 'Memory Used: ' . round(\$status['memory_usage']['used_memory']/1024/1024, 2) . 'MB / ' .
     round((\$status['memory_usage']['used_memory'] + \$status['memory_usage']['free_memory'])/1024/1024, 2) . 'MB' . PHP_EOL;
echo 'Cached Scripts: ' . \$status['opcache_statistics']['num_cached_scripts'] . PHP_EOL;
echo 'Hit Rate: ' . round(\$status['opcache_statistics']['opcache_hit_rate'], 2) . '%' . PHP_EOL;
"
```

**Expected:**
- Memory Used: < 512MB
- Hit Rate: > 95%

---

## 4. Test APCu User Cache

### Test 1: Check APCu is Loaded

```bash
# Check APCu extension
docker exec wisski-performance-tuned-drupal php -m | grep apcu

# Expected: apcu
```

### Test 2: APCu Statistics

```bash
# Check APCu status
docker exec wisski-performance-tuned-drupal php -r "print_r(apcu_cache_info());"

# Look for:
# [num_entries] - Should have entries
# [mem_size] - Should be using memory
```

---

## 5. Test MariaDB Optimizations

### Test 1: Check InnoDB Buffer Pool

```bash
# Check buffer pool size
docker exec wisski-performance-tuned-mariadb mysql -u root -p${DB_ROOT_PASSWORD:-ROOTPW} -e "
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
"

# Expected: 1073741824 (1GB)
```

### Test 2: Check InnoDB Settings

```bash
# Verify optimizations are applied
docker exec wisski-performance-tuned-mariadb mysql -u root -p${DB_ROOT_PASSWORD:-ROOTPW} -e "
SHOW VARIABLES WHERE Variable_name IN (
  'innodb_buffer_pool_size',
  'innodb_log_file_size',
  'innodb_flush_log_at_trx_commit',
  'innodb_flush_method',
  'max_connections',
  'query_cache_size'
);
"
```

**Expected values:**
- innodb_buffer_pool_size: 1073741824 (1GB)
- innodb_log_file_size: 268435456 (256MB)
- innodb_flush_log_at_trx_commit: 2
- innodb_flush_method: O_DIRECT
- max_connections: 200
- query_cache_size: 67108864 (64MB)

### Test 3: Check Buffer Pool Efficiency

```bash
# Check buffer pool hit rate
docker exec wisski-performance-tuned-mariadb mysql -u root -p${DB_ROOT_PASSWORD:-ROOTPW} -e "
SHOW STATUS LIKE 'Innodb_buffer_pool%';
"

# Calculate hit rate:
# hit_rate = (reads - read_requests) / reads * 100
# Should be > 95%
```

### Test 4: Query Cache Statistics

```bash
# Check query cache efficiency
docker exec wisski-performance-tuned-mariadb mysql -u root -p${DB_ROOT_PASSWORD:-ROOTPW} -e "
SHOW STATUS LIKE 'Qcache%';
"

# Look for:
# Qcache_hits - Should be growing
# Qcache_inserts - Queries added to cache
# Hit ratio = Qcache_hits / (Qcache_hits + Qcache_inserts)
```

**Good hit ratio:** > 80%

---

## 6. Test Apache Performance

### Test 1: Check Compression

```bash
# Test Gzip compression
curl -H "Accept-Encoding: gzip" -I http://localhost:80

# Look for: Content-Encoding: gzip
```

### Test 2: Check Brotli Compression

```bash
# Test Brotli compression
curl -H "Accept-Encoding: br" -I http://localhost:80

# Look for: Content-Encoding: br
```

### Test 3: Check Caching Headers

```bash
# Test for browser caching headers
curl -I http://localhost:80/core/misc/drupal.js

# Look for:
# Cache-Control: max-age=31536000, public
# Expires: (date ~1 year in future)
```

### Test 4: Check HTTP/2

```bash
# Check if HTTP/2 is available (requires HTTPS)
docker exec wisski-performance-tuned-drupal apache2ctl -M | grep http2

# Should show: http2_module (shared)
# Note: HTTP/2 only works over HTTPS
```

### Test 5: Security Headers

```bash
# Check security headers
curl -I http://localhost:80

# Look for:
# X-Content-Type-Options: nosniff
# X-Frame-Options: SAMEORIGIN
# X-XSS-Protection: 1; mode=block
```

---

## 7. Overall Performance Testing

### Test 1: Page Load Time Comparison

```bash
# Install apache-bench if not available
# sudo pacman -S apache-tools  # (for Arch/CachyOS)

# Test direct Drupal (no Varnish)
ab -n 100 -c 10 http://localhost:80/

# Test via Varnish
ab -n 100 -c 10 http://localhost:8000/

# Compare:
# - Requests per second (higher is better)
# - Time per request (lower is better)
```

### Test 2: Concurrent User Load

```bash
# Simulate 50 concurrent users
ab -n 500 -c 50 http://localhost:8000/

# Check for:
# - Failed requests: 0
# - Requests per second: should be high (>100)
# - No container crashes
```

### Test 3: Memory Usage

```bash
# Check resource usage
docker stats --no-stream

# Verify containers are within resource limits
```

### Test 4: Response Time Measurement

```bash
# Detailed timing breakdown
curl -w "\n\
    time_namelookup:  %{time_namelookup}s\n\
       time_connect:  %{time_connect}s\n\
    time_appconnect:  %{time_appconnect}s\n\
   time_pretransfer:  %{time_pretransfer}s\n\
      time_redirect:  %{time_redirect}s\n\
 time_starttransfer:  %{time_starttransfer}s\n\
                    ----------\n\
         time_total:  %{time_total}s\n" \
-o /dev/null -s http://localhost:8000/

# First request (cache miss): ~0.5-2s
# Cached request: ~0.02-0.05s (20-100x faster!)
```

---

## 8. Integration Tests

### Test 1: Full Stack Test

```bash
# Test entire request flow
echo "Testing full stack..."

# 1. Varnish → Drupal
curl -s -o /dev/null -w "Varnish: %{http_code}\n" http://localhost:8000/

# 2. Check Redis has data
REDIS_KEYS=$(docker exec wisski-performance-tuned-redis redis-cli DBSIZE | grep -oP '\d+')
echo "Redis keys: $REDIS_KEYS"

# 3. Check MariaDB connection
docker exec wisski-performance-tuned-drupal drush sql:query "SELECT 1;" && echo "Database: OK"

# 4. Check RDF4J
curl -s -o /dev/null -w "RDF4J: %{http_code}\n" http://localhost:8080/rdf4j-server/

echo "✅ Full stack test complete!"
```

### Test 2: Cache Invalidation Test

```bash
# Test that cache clears properly
echo "Testing cache invalidation..."

# 1. Clear Drupal cache
docker exec wisski-performance-tuned-drupal drush cr

# 2. Clear Redis
docker exec wisski-performance-tuned-redis redis-cli FLUSHALL

# 3. Purge Varnish cache
docker exec wisski-performance-tuned-varnish varnishadm "ban req.url ~ ."

# 4. Access site again (should rebuild cache)
curl -s http://localhost:8000/ > /dev/null

echo "✅ Cache invalidation test complete!"
```

---

## 9. Automated Test Script

Save this as `test-performance.sh`:

```bash
#!/bin/bash
set -e

cd /home/rnsrk/sites/wisski-dev/tuned

echo "🧪 WissKI Performance Test Suite"
echo "================================"
echo ""

# Test 1: Container Health
echo "1️⃣  Testing container health..."
UNHEALTHY=$(docker compose ps | grep -v "healthy\|Up" | grep -c "wisski" || true)
if [ $UNHEALTHY -eq 0 ]; then
    echo "   ✅ All containers healthy"
else
    echo "   ❌ Some containers unhealthy"
    docker compose ps
fi
echo ""

# Test 2: Varnish Cache
echo "2️⃣  Testing Varnish cache..."
RESPONSE=$(curl -s -I http://localhost:8000/)
if echo "$RESPONSE" | grep -q "Via.*varnish"; then
    echo "   ✅ Varnish is active"
    if echo "$RESPONSE" | grep -q "X-Varnish-Cache: HIT"; then
        echo "   ✅ Cache hit detected"
    else
        echo "   ⚠️  Cache miss (expected on first run)"
    fi
else
    echo "   ❌ Varnish not responding"
fi
echo ""

# Test 3: Redis
echo "3️⃣  Testing Redis..."
if docker exec wisski-performance-tuned-redis redis-cli ping | grep -q "PONG"; then
    echo "   ✅ Redis responding"
    KEYS=$(docker exec wisski-performance-tuned-redis redis-cli DBSIZE | grep -oP '\d+')
    echo "   📊 Redis keys: $KEYS"
else
    echo "   ❌ Redis not responding"
fi
echo ""

# Test 4: PHP OPcache
echo "4️⃣  Testing PHP OPcache..."
OPCACHE=$(docker exec wisski-performance-tuned-drupal php -i | grep "opcache.enable =>" | head -1)
if echo "$OPCACHE" | grep -q "On"; then
    echo "   ✅ OPcache enabled"
else
    echo "   ❌ OPcache disabled"
fi
echo ""

# Test 5: MariaDB
echo "5️⃣  Testing MariaDB optimizations..."
BUFFER_POOL=$(docker exec wisski-performance-tuned-mariadb mysql -u root -pROOTPW -se "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null | awk '{print $2}')
if [ "$BUFFER_POOL" = "1073741824" ]; then
    echo "   ✅ InnoDB buffer pool: 1GB"
else
    echo "   ⚠️  InnoDB buffer pool: $BUFFER_POOL bytes"
fi
echo ""

# Test 6: Response Time
echo "6️⃣  Testing response time..."
TIME=$(curl -o /dev/null -s -w '%{time_total}\n' http://localhost:8000/)
echo "   ⏱️  Page load: ${TIME}s"
if (( $(echo "$TIME < 0.1" | bc -l) )); then
    echo "   ✅ Excellent response time!"
elif (( $(echo "$TIME < 0.5" | bc -l) )); then
    echo "   ✅ Good response time"
else
    echo "   ⚠️  Could be faster (cache may not be warm)"
fi
echo ""

echo "================================"
echo "✅ Performance test suite complete!"
echo ""
echo "💡 Tips:"
echo "   - Run tests multiple times to warm up caches"
echo "   - Compare response times with 'slow' environment"
echo "   - Monitor with: docker stats"
```

Make it executable and run:

```bash
chmod +x test-performance.sh
./test-performance.sh
```

---

## 10. Expected Performance Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Varnish Cache Hit Rate** | > 80% | `varnishstat -1 \| grep cache_hit` |
| **Redis Hit Rate** | > 90% | `redis-cli INFO stats` |
| **OPcache Hit Rate** | > 95% | PHP opcache statistics |
| **Page Load Time (cached)** | < 100ms | `curl -w "%{time_total}"` |
| **Page Load Time (uncached)** | < 2s | First request timing |
| **Concurrent Users** | > 100 | `ab -n 1000 -c 100` |
| **Memory Usage** | ~8-10GB total | `docker stats` |
| **Database Hit Rate** | > 95% | InnoDB buffer pool stats |

---

## 11. Troubleshooting

### Varnish Not Caching?

```bash
# Check VCL compilation
docker logs wisski-performance-tuned-varnish

# Check if you're logged in (Varnish doesn't cache authenticated users)
curl -I http://localhost:8000/ | grep Cookie
```

### Redis Not Working?

```bash
# Check Redis logs
docker logs wisski-performance-tuned-redis

# Check Drupal settings
docker exec wisski-performance-tuned-drupal cat /var/www/html/sites/default/settings.php | grep redis
```

### Poor Performance?

```bash
# Check resource usage
docker stats

# Check for errors
docker compose logs --tail 50

# Rebuild and restart
docker compose down
docker compose up -d --build
```

---

## 12. Comparison Test

Test against the "slow" environment:

```bash
# Start slow environment
cd /home/rnsrk/sites/wisski-dev/slow
docker compose up -d

# Wait 60 seconds for warmup
sleep 60

# Test slow
time curl -s http://localhost:80 > /dev/null

# Start tuned environment
cd /home/rnsrk/sites/wisski-dev/tuned
docker compose up -d

# Wait 60 seconds for warmup
sleep 60

# Test tuned (first load - cache miss)
time curl -s http://localhost:8000 > /dev/null

# Test tuned (second load - cache hit)
time curl -s http://localhost:8000 > /dev/null

# Compare the times!
```

**Expected Results:**
- Slow: ~2-3 seconds
- Tuned (uncached): ~0.5-1 second (2-3x faster)
- Tuned (cached): ~0.02-0.05 seconds (**40-100x faster!**)

---

## Summary: Quick Verification Checklist

- [ ] All containers show as healthy: `docker compose ps`
- [ ] Varnish responds with cache headers: `curl -I http://localhost:8000`
- [ ] Redis responds to ping: `docker exec ... redis-cli ping`
- [ ] OPcache is enabled: `docker exec ... php -i | grep opcache.enable`
- [ ] MariaDB buffer pool is 1GB: Check with MySQL command
- [ ] Page loads in < 100ms (cached): `curl -w "%{time_total}"`
- [ ] No errors in logs: `docker compose logs`

If all checks pass: **🎉 Your performance-tuned environment is working perfectly!**

