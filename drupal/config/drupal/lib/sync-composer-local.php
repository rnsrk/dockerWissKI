#!/usr/bin/env php
<?php

/**
 * Write web/sites/composer.local.json from extras in the live composer.json
 * that are not in the image's baked composer.json.
 */
$root = '/opt/drupal';
$bakedFile = $root . '/.wisski-composer.json';
$liveFile = $root . '/composer.json';
$localFile = $root . '/web/sites/composer.local.json';

if (!is_readable($bakedFile) || !is_readable($liveFile)) {
  fwrite(STDERR, "Missing baked or live composer.json\n");
  exit(1);
}

$baked = json_decode((string) file_get_contents($bakedFile), true) ?: [];
$live = json_decode((string) file_get_contents($liveFile), true) ?: [];
$bakedRequire = $baked['require'] ?? [];
$liveRequire = $live['require'] ?? [];

$extras = [];
foreach ($liveRequire as $package => $constraint) {
  if ($package === 'php' || str_starts_with($package, 'ext-')) {
    continue;
  }
  if (!array_key_exists($package, $bakedRequire) || $bakedRequire[$package] !== $constraint) {
    $extras[$package] = $constraint;
  }
}

if ($extras === []) {
  if (is_file($localFile)) {
    unlink($localFile);
  }
  fwrite(STDOUT, "No extra Composer packages; composer.local.json removed if present.\n");
  exit(0);
}

ksort($extras);
$payload = ['require' => $extras];
if (!is_dir(dirname($localFile))) {
  mkdir(dirname($localFile), 0775, true);
}
file_put_contents(
  $localFile,
  json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n"
);
fwrite(STDOUT, "Wrote " . $localFile . " with " . count($extras) . " package(s).\n");
