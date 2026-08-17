# Docker WissKI

Standalone WissKI stack with a PHP-FPM Drupal image, PostgreSQL 16, [OpenGDB](https://github.com/FAU-CDI/open_gdb), Solr, Redis, Varnish, and pgAdmin.

This repository builds and publishes its own images. It does not depend on the SODA SCS stack.

## Images

| Image | When to use |
| --- | --- |
| `ghcr.io/rnsrk/dockerwisski-production` | OPcache on, no Xdebug, Varnish in front |
| `ghcr.io/rnsrk/dockerwisski-development` | OPcache off, Xdebug on port 9003, Drupal is the HTTP entry |

After the first GitHub Actions publish, set the GHCR packages to **public** so pulls do not need a token.

## Quick start

```bash
git clone --recurse-submodules git@github.com:rnsrk/dockerWissKI.git
cd dockerWissKI
cp env/development.env .env   # or: cp env/production.env .env
# Edit secrets in .env (Django, Postgres, Drupal passwords)
docker compose up -d
```

First boot installs Drupal and WissKI recipes; that can take several minutes. Follow with `docker compose logs -f drupal`.

### Development vs production

| | Development (`env/development.env`) | Production (`env/production.env`) |
| --- | --- | --- |
| Image | `dockerwisski-development` | `dockerwisski-production` |
| Public HTTP (`HTTP_PORT`, default 80) | Drupal | Varnish |
| Varnish | off | on (`COMPOSE_PROFILES` includes `production`) |
| Xdebug | port 9003, trigger mode | not installed |
| Page cache | off | 5 minutes |
| Drupal bypass | n/a | `127.0.0.1:8082` |

pgAdmin is the Compose profile `tools` (enabled in both presets). Omit it by removing `tools` from `COMPOSE_PROFILES`.

Apple Silicon: append `docker-compose.apple-silicon.yml` to `COMPOSE_FILE` in `.env`.

## Access

| What | URL (defaults) |
| --- | --- |
| Site | http://localhost (`HTTP_PORT`) |
| OpenGDB / Django admin | http://localhost:8080 (`PUBLIC_PORT`) |
| pgAdmin | http://localhost:8081 |
| Solr | http://localhost:8983 |
| Drupal direct (production preset only) | http://127.0.0.1:8082 |

OpenGDB login is `DJANGO_SUPERUSER_NAME` / `DJANGO_SUPERUSER_PASSWORD`. Drupal SPARQL uses the same user via `TS_USERNAME` / `TS_PASSWORD` (or `TS_TOKEN` from `/api-token-auth/`). Create or keep the `default` repository; the Drupal entrypoint tries to PUT it on first install.

## Layout

```
docker-compose.yml                 # core services, include OpenGDB
docker-compose.override.yml        # local build + operator ports
docker-compose.development.yml     # HTTP → Drupal, Xdebug
docker-compose.production.yml      # HTTP → Varnish
env/development.env
env/production.env
drupal/                            # image (Dockerfile, entrypoint, PHP/Nginx)
opengdb/                           # git submodule (FAU-CDI/open_gdb)
config/                            # Postgres init, Varnish VCL, pgAdmin servers.json
```

`.env` sets `COMPOSE_FILE` and `MODE`. With `COMPOSE_FILE` set, Compose loads exactly those files (no implicit extra merge).

Build the Drupal image locally (also happens on `compose up` when the GHCR tag is missing):

```bash
docker compose build drupal
```

## Updating OpenGDB

```bash
git submodule update --remote opengdb
```

Pin the new submodule commit in this repository when it works.

## Extra modules, libraries, and custom code

The Drupal codebase in the image is replaced on every container recreate. Binding `composer.json` / `vendor` / `web/modules/contrib` as volumes would hide the new image and desync lock files.

Instead:

| What | Where it lives | How to add it |
| --- | --- | --- |
| Drupal core, WissKI, image packages | Image | Pull a new image |
| Extra Composer packages (contrib modules, libraries) | `web/sites/composer.local.json` on the sites volume | `docker compose exec drupal wisski-composer require drupal/webform:^6.2` |
| Custom modules | volume `web/modules/custom` | copy or bind-mount your code |
| Custom themes | volume `web/themes/custom` | copy or bind-mount your code |
| Uploads / settings | `web/sites`, private files | already persistent |

On every boot the entrypoint restores the **image** `composer.json` (and lock), then `composer require`s whatever is in `composer.local.json`. Composer cache is a volume, so repeats are fast. After an image upgrade, extras are installed on top of the new Drupal; if a constraint cannot be satisfied, the container exits until you fix `composer.local.json`.

Example file: [`config/drupal/composer.local.json.example`](config/drupal/composer.local.json.example). Do not run plain `composer require` — it would not be recorded on the sites volume.

```bash
docker compose exec drupal wisski-composer require drupal/webform:^6.2
docker compose exec drupal drush en webform -y
docker compose exec drupal drush cr
```

## License

See [LICENSE](LICENSE).
