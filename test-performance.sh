#!/bin/bash
set -e

cd /home/rnsrk/sites/wisski-dev/tuned

echo "🧪 WissKI Performance Test Suite"
echo "================================"
echo ""

# Test 1: Container Health.
echo "1️⃣  Testing container health..."
UNHEALTHY=$(docker compose ps | grep -v "healthy\|Up" | grep -c "wisski" || true)
if [ $UNHEALTHY -eq 0 ]; then
    echo "   ✅ All containers healthy"
else
    echo "   ❌ Some containers unhealthy"
    docker compose ps
fi
echo ""

# Test 2: Varnish Cache.
echo "2️⃣  Testing Varnish cache..."
RESPONSE=$(curl -s -I http://localhost:8000/ 2>&1)
if echo "$RESPONSE" | grep -qi "X-Varnish-Cache"; then
    echo "   ✅ Varnish is active"
    if echo "$RESPONSE" | grep -q "X-Varnish-Cache: HIT"; then
        echo "   ✅ Cache hit detected"
    else
        echo "   ⚠️  Cache miss (warming cache)"
    fi
    # Test again for cache hit
    sleep 1
    RESPONSE2=$(curl -s -I http://localhost:8000/ 2>&1)
    if echo "$RESPONSE2" | grep -q "X-Varnish-Cache: HIT"; then
        AGE=$(echo "$RESPONSE2" | grep "^Age:" | awk '{print $2}' | tr -d '\r')
        echo "   ✅ Second request cached (Age: ${AGE}s)"
    fi
else
    echo "   ❌ Varnish not responding"
fi
echo ""

# Test 3: Redis.
echo "3️⃣  Testing Redis..."
if docker exec wisski-performance-tuned-redis redis-cli ping | grep -q "PONG"; then
    echo "   ✅ Redis responding"
    KEYS=$(docker exec wisski-performance-tuned-redis redis-cli DBSIZE | grep -oP '\d+')
    echo "   📊 Redis keys: $KEYS"
else
    echo "   ❌ Redis not responding"
fi
echo ""

# Test 4: PHP OPcache.
echo "4️⃣  Testing PHP OPcache..."
OPCACHE=$(docker exec wisski-performance-tuned-drupal php -i | grep "opcache.enable =>" | head -1)
if echo "$OPCACHE" | grep -q "On"; then
    echo "   ✅ OPcache enabled"
    # Get JIT status.
    JIT=$(docker exec wisski-performance-tuned-drupal php -i | grep "opcache.jit =>" | head -1)
    if echo "$JIT" | grep -q "tracing"; then
        echo "   ✅ JIT compiler enabled (tracing mode)"
    fi
else
    echo "   ❌ OPcache disabled"
fi
echo ""

# Test 5: MariaDB.
echo "5️⃣  Testing MariaDB optimizations..."
BUFFER_POOL=$(docker exec wisski-performance-tuned-mariadb mysql -u root -p${DB_ROOT_PASSWORD:-ROOTPW} -se "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null | awk '{print $2}')
if [ "$BUFFER_POOL" = "1073741824" ]; then
    echo "   ✅ InnoDB buffer pool: 1GB"
else
    echo "   ⚠️  InnoDB buffer pool: $(echo $BUFFER_POOL | numfmt --to=iec 2>/dev/null || echo $BUFFER_POOL bytes)"
fi
echo ""

# Test 6: Response Time.
echo "6️⃣  Testing response time..."
echo "   First request (warming cache)..."
curl -s -o /dev/null http://localhost:8000/
sleep 1

echo "   Second request (should be cached)..."
TIME=$(curl -o /dev/null -s -w '%{time_total}\n' http://localhost:8000/)
echo "   ⏱️  Page load: ${TIME}s"
if (( $(echo "$TIME < 0.1" | bc -l 2>/dev/null || echo "0") )); then
    echo "   ✅ Excellent response time! (< 100ms)"
elif (( $(echo "$TIME < 0.5" | bc -l 2>/dev/null || echo "1") )); then
    echo "   ✅ Good response time (< 500ms)"
else
    echo "   ⚠️  Could be faster (cache may not be warm)"
fi
echo ""

# Test 7: Apache Compression.
echo "7️⃣  Testing Apache compression..."
GZIP=$(curl -s -H "Accept-Encoding: gzip" -I http://localhost:80/ | grep -i "Content-Encoding")
if echo "$GZIP" | grep -q "gzip"; then
    echo "   ✅ Gzip compression enabled"
elif echo "$GZIP" | grep -q "br"; then
    echo "   ✅ Brotli compression enabled"
else
    echo "   ⚠️  No compression detected (may be too small response)"
fi
echo ""

# Test 8: Redis Module in Drupal.
echo "8️⃣  Testing Drupal Redis module..."
if docker exec wisski-performance-tuned-drupal drush pm:list --status=enabled 2>/dev/null | grep -q "redis"; then
    echo "   ✅ Redis module enabled in Drupal"
else
    echo "   ⚠️  Redis module not enabled (may not be installed yet)"
fi
echo ""

echo "================================"
echo "✅ Performance test suite complete!"
echo ""
echo "📊 Summary:"
echo "   - For detailed tests: see TESTING.md"
echo "   - Monitor resources: docker stats"
echo "   - View logs: docker compose logs"
echo ""
echo "💡 Tips:"
echo "   - Run tests multiple times to warm up caches"
echo "   - Access via Varnish (port 8000) for best performance"
echo "   - Compare with 'slow' environment to see improvement"

