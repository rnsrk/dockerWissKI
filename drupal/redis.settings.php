<?php

/**
 * Redis cache backend configuration for WissKI.
 *
 * This file configures Drupal to use Redis for caching when available.
 * The Redis module must be installed via Composer.
 */

// Only configure Redis if the extension is loaded and connection is available.
if (extension_loaded('redis')) {
  // Redis connection settings from environment variables.
  $redisHost = getenv('REDIS_HOST') ?: 'redis';
  $redisPort = getenv('REDIS_PORT') ?: 6379;

  // Test Redis connection before configuring.
  try {
    $redis = new Redis();
    if (@$redis->connect($redisHost, $redisPort, 2)) {
      $redis->close();

      // Configure Redis connection.
      $settings['redis.connection']['interface'] = 'PhpRedis';
      $settings['redis.connection']['host'] = $redisHost;
      $settings['redis.connection']['port'] = $redisPort;

      // Optional: Set a prefix for cache keys (useful for multiple sites).
      // $settings['redis.connection']['base'] = 0;
      // $settings['redis.connection']['persistent'] = TRUE;

      // Set Redis as the default cache backend.
      $settings['cache']['default'] = 'cache.backend.redis';

      // Keep the database cache for the Form cache bin (required for Drupal).
      $settings['cache']['bins']['form'] = 'cache.backend.database';

      // Optional: Use Redis for additional bins.
      $settings['cache']['bins']['bootstrap'] = 'cache.backend.redis';
      $settings['cache']['bins']['render'] = 'cache.backend.redis';
      $settings['cache']['bins']['data'] = 'cache.backend.redis';
      $settings['cache']['bins']['discovery'] = 'cache.backend.redis';

      // Configure Redis services for better performance.
      if (file_exists('modules/contrib/redis/redis.services.yml')) {
        $settings['container_yamls'][] = 'modules/contrib/redis/redis.services.yml';
      }
      if (file_exists('modules/contrib/redis/example.services.yml')) {
        $settings['container_yamls'][] = 'modules/contrib/redis/example.services.yml';
      }

      // Manually add the classloader path for Redis module.
      if (file_exists($app_root . '/modules/contrib/redis/src')) {
        $class_loader->addPsr4('Drupal\\redis\\', 'modules/contrib/redis/src');
      }

      // Configure bootstrap container to use Redis (improves performance).
      $settings['bootstrap_container_definition'] = [
        'parameters' => [],
        'services' => [
          'redis.factory' => [
            'class' => 'Drupal\redis\ClientFactory',
          ],
          'cache.backend.redis' => [
            'class' => 'Drupal\redis\Cache\CacheBackendFactory',
            'arguments' => ['@redis.factory', '@cache_tags_provider.container', '@serialization.phpserialize'],
          ],
          'cache.container' => [
            'class' => '\Drupal\redis\Cache\PhpRedis',
            'factory' => ['@cache.backend.redis', 'get'],
            'arguments' => ['container'],
          ],
          'cache_tags_provider.container' => [
            'class' => 'Drupal\redis\Cache\RedisCacheTagsChecksum',
            'arguments' => ['@redis.factory'],
          ],
          'serialization.phpserialize' => [
            'class' => 'Drupal\Component\Serialization\PhpSerialize',
          ],
        ],
      ];
    }
  } catch (Exception $e) {
    // Redis connection failed, continue without Redis caching.
    error_log('Redis connection failed: ' . $e->getMessage());
  }
}

