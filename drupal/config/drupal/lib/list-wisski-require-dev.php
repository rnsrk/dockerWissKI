#!/usr/bin/env php
<?php

/**
 * Print the WissKI test dependencies as Composer specs (name:constraint), one per line.
 *
 * Like the GitLab CI composer job: the module's require-dev plus every
 * `suggest` package as name:*. Some test modules depend on them, e.g.
 * wisski_authfile on drupal/action (no longer in core 11). phpunit is
 * omitted: drupal/core-dev pins the version that matches core. Suggestions the
 * site composer.json (second argument) already requires are skipped, so
 * `composer require --dev` does not move them out of `require`.
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

$siteRequire = [];
$siteFile = $argv[2] ?? '';
if ($siteFile !== '') {
  $site = is_readable($siteFile) ? json_decode((string) file_get_contents($siteFile), true) : NULL;
  if (!is_array($site)) {
    fwrite(STDERR, "Site composer.json not readable: {$siteFile}\n");
    exit(1);
  }
  $siteRequire = $site['require'] ?? [];
}

$skip = static fn($name): bool => !is_string($name) || $name === 'phpunit/phpunit' || $name === 'php' || str_starts_with($name, 'ext-');

foreach ($json['require-dev'] ?? [] as $name => $constraint) {
  if (!$skip($name)) {
    echo $name, ':', $constraint, PHP_EOL;
  }
}

foreach (array_keys($json['suggest'] ?? []) as $name) {
  if (!$skip($name) && !isset($siteRequire[$name]) && !isset($json['require-dev'][$name])) {
    echo $name, ':*', PHP_EOL;
  }
}
