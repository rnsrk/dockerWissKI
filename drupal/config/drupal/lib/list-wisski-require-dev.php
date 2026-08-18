#!/usr/bin/env php
<?php

/**
 * Print WissKI require-dev package specs (name:constraint), one per line.
 * phpunit is omitted (needs drupal/core-dev). Empty stdout means skip require.
 */
$file = $argv[1] ?? '';
if ($file === '' || !is_readable($file)) {
  fwrite(STDERR, "WissKI composer.json not readable: {$file}\n");
  exit(1);
}

$json = json_decode((string) file_get_contents($file), true);
if (!is_array($json)) {
  fwrite(STDERR, "WissKI composer.json is not valid JSON: {$file}\n");
  exit(1);
}

foreach ($json['require-dev'] ?? [] as $name => $constraint) {
  if (!is_string($name) || $name === 'phpunit/phpunit' || $name === 'php' || str_starts_with($name, 'ext-')) {
    continue;
  }
  echo $name, ':', $constraint, PHP_EOL;
}
