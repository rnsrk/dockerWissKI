# Docker WissKI

Standalone WissKI stack with a PHP-FPM Drupal image, PostgreSQL 16, [OpenGDB](https://github.com/FAU-CDI/open_gdb), Redis, Varnish, and pgAdmin. Solr is optional.

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
# Change all passwords and emails in .env
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
| Lint tools | phpcs, phpstan, cspell (baked in) | not included |
| Page cache | off | 5 minutes |
| Drupal bypass | n/a | `127.0.0.1:8082` |

pgAdmin is the Compose profile `tools` (enabled in both presets). Omit it by removing `tools` from `COMPOSE_PROFILES`. Solr is the profile `solr` (off by default); add `solr` to `COMPOSE_PROFILES` when Search API needs it.

Redis persistence is RDB only. Background saves need `vm.overcommit_memory=1` on the **host** (Docker cannot set this inside the container): `sudo sysctl -w vm.overcommit_memory=1`.

Drupal concurrency is set in `.env` (recreate the container after changing):

| Variable | Default (dev / prod) | What it sizes |
| --- | --- | --- |
| `DRUPAL_CPUS` | `6.0` / `2.0` | Drupal cgroup CPU |
| `DRUPAL_MEMORY` | `4G` / `2G` | Drupal cgroup RAM |
| `NGINX_WORKER_PROCESSES` | `4` / `2` | Nginx workers (`auto` uses host nproc) |
| `PHP_FPM_MAX_CHILDREN` | `8` / `6` | Concurrent PHP requests |

Raising nginx workers without `DRUPAL_CPUS` / `PHP_FPM_MAX_CHILDREN` does not speed Drupal up. SPARQL can approach 1G per PHP child, so keep `PHP_FPM_MAX_CHILDREN` in line with `DRUPAL_MEMORY`. `NGINX_WORKER_PROCESSES` and `PHP_FPM_MAX_CHILDREN` are applied at container start (need an image that includes that entrypoint).

Apple Silicon: append `docker-compose.apple-silicon.yml` to `COMPOSE_FILE` in `.env`. Local Drupal image build: append `docker-compose.local-build.yml`. Machine-local tweaks: copy `docker-compose.override.yml.example` to `docker-compose.override.yml` (gitignored) and append that file last.

## Access

| What | URL (defaults) |
| --- | --- |
| Site | http://localhost (`HTTP_PORT`) |
| Drupal login | `DRUPAL_USER` / `DRUPAL_PASSWORD` |
| OpenGDB / Django admin | http://localhost:8080 (`PUBLIC_PORT`) |
| pgAdmin | http://localhost:8081 (`PGADMIN_PORT`) |
| Solr (optional `solr` profile) | http://localhost:8983 (`SOLR_PORT`) |
| Drupal direct (production preset only) | http://127.0.0.1:8082 (`DRUPAL_DIRECT_PORT`) |

OpenGDB login is `DJANGO_SUPERUSER_NAME` / `DJANGO_SUPERUSER_PASSWORD`. On first install the Drupal entrypoint creates the `default` repository through OpenGDB (`POST /rest/repositories`) and fails if SPARQL does not return HTTP 200.

Drupal SPARQL talks to **authproxy**, not to the OpenGDB `nginx` service and not to RDF4J:

| Path | URL |
| --- | --- |
| Browser / Django admin | http://localhost:8080 (`PUBLIC_PORT`) → OpenGDB nginx → authproxy |
| Drupal SPARQL (internal) | `http://authproxy:8000/repositories/default` |
| Raw RDF4J (do not use from Drupal) | `http://rdf4j:8080/rdf4j-server/repositories/default` |

Hitting RDF4J directly skips OpenGDB login and repository ACLs. `nginx` in this stack is OpenGDB’s reverse proxy for port 8080; it is not Drupal’s web server.

### Django admin, users, and SPARQL tokens

OpenGDB’s Django admin is [http://localhost:8080/admin](http://localhost:8080/admin) (`PUBLIC_PORT`). Log in with `DJANGO_SUPERUSER_NAME` / `DJANGO_SUPERUSER_PASSWORD`.

By default Drupal SPARQL uses HTTP Basic with `TS_USERNAME` / `TS_PASSWORD` (same user as the Django superuser). OpenGDB also supports **token** auth, which avoids hashing the password on every SPARQL request. Use tokens over **HTTPS** in production ([OpenGDB note](https://github.com/FAU-CDI/open_gdb#token-authentication)).

1. **Optional dedicated user.** In Django admin → **Users**, add a user and give it rights on the `default` repository (RDF4J options / permissions). Or keep using the superuser.
2. **Get a token** (form fields, not JSON):

```bash
curl -sS -X POST "http://localhost:8080/api-token-auth/" \
  -d username=YOUR_USER -d password=YOUR_PASSWORD
# {"token":"..."}
```

The same token is listed in Django admin under **Auth Token → Tokens**.

3. **Fresh install.** Set `TS_TOKEN` in `.env` **before** the first `docker compose up`. The entrypoint then creates the WissKI SALZ adapter with token auth (`TS_USERNAME` / `TS_PASSWORD` can stay empty). Changing `TS_TOKEN` later does **not** rewrite an existing adapter.
4. **Existing site.** Drupal → **Configuration → WissKI SALZ → Adapters** → Default (`/admin/config/wisski_salz/adapter/default/edit`) → enable token authentication, paste the token, save, then `docker compose exec drupal drush cr`.

If Drupal SPARQL fails after recreating authproxy, wait until `docker compose ps authproxy` is healthy and retry. On every boot the entrypoint rewrites the Default SALZ adapter read/write URLs from `TS_READ_URL` / `TS_WRITE_URL`; it does not rewrite the stored token or password. OpenGDB’s public UI (port 8080) still goes through nginx; a 502 there usually means nginx still has a stale authproxy IP — `docker compose up -d --force-recreate nginx`.

## Layout

```
docker-compose.yml                      # default stack, include OpenGDB
docker-compose.development.yml          # HTTP → Drupal, Xdebug
docker-compose.production.yml           # HTTP → Varnish
docker-compose.local-build.yml          # optional: build Drupal locally (append)
docker-compose.apple-silicon.yml        # optional: amd64 via Rosetta (append)
docker-compose.override.yml.example     # template for machine-local overlay
env/development.env                     # copy to .env for development
env/production.env                      # copy to .env for production
drupal/                                 # PHP 8.3 FPM image (Dockerfile, entrypoint, PHP/Nginx)
opengdb/                                # git submodule (FAU-CDI/open_gdb)
config/postgres/                        # Postgres init (pg_trgm)
config/varnish/default.vcl              # Varnish (production profile)
config/pgadmin/                         # pgAdmin servers.json (filled from DB_* on start)
config/opengdb/                         # RDF4J entrypoint, nginx DNS TTL
config/drupal/                          # example composer.local.json
drupal/config/                          # PHP, Nginx, Redis baked into the image
```

`.env` sets `COMPOSE_FILE` and `MODE`. With `COMPOSE_FILE` set, Compose loads **exactly** those files (no implicit `docker-compose.override.yml` merge). The presets are:

| Preset | `COMPOSE_FILE` |
| --- | --- |
| Development | `docker-compose.yml:docker-compose.development.yml` |
| Production | `docker-compose.yml:docker-compose.production.yml` |

Optional files are **not** in the presets. Append them in `.env` when needed, last file wins:

```bash
# Local image build (uses WISSKI_PACKAGES_VERSION / WISSKI_PACKAGES_LINE, currently 3.7.0 / 3.x)
COMPOSE_FILE=docker-compose.yml:docker-compose.development.yml:docker-compose.local-build.yml

# Then: docker compose build drupal
# or:   docker compose up -d --build
```

`docker-compose.override.yml` is gitignored. Copy the example and append it last for bind-mounts, extra ports, or other machine-only changes.

The development image installs WissKI’s PHP lint tools from the module `require-dev` when that key exists (WissKI 4.x; 3.x `scs_base` has none) and global `cspell`. Do not put those packages in `composer.local.json`.

## Updating OpenGDB

```bash
git submodule update --remote opengdb
```

Pin the new submodule commit in this repository when it works.

## Extra modules, libraries, and custom code

The Drupal codebase in the image is replaced on every container start. Binding `composer.json` / `vendor` / `web/modules/contrib` as volumes would hide the new image and desync lock files.

**Warning:** `docker compose exec drupal composer require …` (or any other install that only writes into the image filesystem) is gone after the next start. The entrypoint restores the image `composer.json` / lock and drops anything that is not recorded in `web/sites/composer.local.json`. Use `wisski-composer` instead.

| What | Where it lives | How to add it |
| --- | --- | --- |
| Drupal core, WissKI, image packages | Image | Pull a new image |
| WissKI lint tools (phpcs, phpstan, cspell) | Development image | baked at build; do not put in `composer.local.json` |
| Extra Composer packages (contrib modules, libraries) | `web/sites/composer.local.json` on the sites volume | `docker compose exec drupal wisski-composer require drupal/webform:^6.2` |
| Custom modules | volume `web/modules/custom` | copy or bind-mount your code |
| Custom themes | volume `web/themes/custom` | copy or bind-mount your code |
| Uploads / settings | `web/sites`, private files | already persistent |

On every boot the entrypoint restores the **image** `composer.json` (and lock), then `composer require`s whatever is in `composer.local.json`. Composer cache is a volume, so repeats are fast. After an image upgrade, extras are installed on top of the new Drupal; if a constraint cannot be satisfied, the container exits until you fix `composer.local.json`.

Example file: [`config/drupal/composer.local.json.example`](config/drupal/composer.local.json.example).

```bash
docker compose exec drupal wisski-composer require drupal/webform:^6.2
docker compose exec drupal drush en webform -y
docker compose exec drupal drush cr
```

## License

See [LICENSE](LICENSE).
