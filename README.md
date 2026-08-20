# Docker WissKI

Standalone WissKI stack with a PHP 8.5 FPM Drupal image, PostgreSQL 17, [OpenGDB](https://github.com/FAU-CDI/open_gdb) (RDF4J 6), Redis 8, Varnish 8, Caddy, and pgAdmin. Solr 10 and the [WissKI Data Importer](https://gitlab.nasarek.dev/rnsrk/wisski_data_importer) UI are optional.

This repository builds and publishes its own images. It does not depend on the SODA SCS stack.

## Images

| Image | When to use |
| --- | --- |
| `ghcr.io/rnsrk/dockerwisski-production` | OPcache on, no Xdebug, Caddy → Varnish |
| `ghcr.io/rnsrk/dockerwisski-development` | OPcache off, Xdebug on port 9003, Caddy → Drupal |

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
| Public HTTP (`HTTP_PORT`, default 80) | Caddy → Drupal | Caddy → Varnish |
| Varnish | off | on (`COMPOSE_PROFILES` includes `production`) |
| Caddy subdomains | `wisski.localhost`, `drupal.wisski.localhost`, … | same; site upstream is Varnish |
| Xdebug | port 9003, trigger mode | not installed |
| Lint tools | phpcs, phpstan, cspell (baked in) | not included |
| Git SSH | `openssh-client`, user `developer` | not included |
| Page cache | off | 5 minutes |
| Drupal bypass | `drupal.wisski.localhost` | `drupal.wisski.localhost` (replaces `127.0.0.1:8082`) |

pgAdmin is the Compose profile `tools` (enabled in both presets). Omit it by removing `tools` from `COMPOSE_PROFILES`. Solr is the profile `solr` (off by default); add `solr` to `COMPOSE_PROFILES` when Search API needs it.

Redis persistence is RDB only. Background saves need `vm.overcommit_memory=1` on the **host** (Docker cannot set this inside the container): `sudo sysctl -w vm.overcommit_memory=1`.

Drupal concurrency is set in `.env` (recreate the container after changing):

| Variable | Default (dev / prod) | What it sizes |
| --- | --- | --- |
| `DRUPAL_CPUS` | `6.0` / `2.0` | Drupal cgroup CPU |
| `DRUPAL_MEMORY` | `4G` / `2G` | Drupal cgroup RAM |
| `NGINX_WORKER_PROCESSES` | `4` / `2` | Nginx workers (`auto` uses host nproc) |
| `PHP_FPM_MAX_CHILDREN` | `8` / `6` | Concurrent PHP requests |
| `RDF4J_CPUS` | `6.0` / `2.0` | RDF4J (SPARQL) cgroup CPU |
| `RDF4J_MEMORY` | `3G` / `1536M` | RDF4J cgroup RAM |
| `RDF4J_HEAP_MAX` | `2g` / `1g` | JVM heap (`-Xmx`; keep ~1G below `RDF4J_MEMORY`) |
| `POSTGRES_CPUS` | `4.0` / `2.0` | PostgreSQL cgroup CPU |
| `POSTGRES_MEMORY` | `2G` / `2G` | PostgreSQL cgroup RAM |

IEF subentity forms and SALZ adapters spend most of their time in SPARQL, not Drupal SQL. Raising `DRUPAL_CPUS` without `RDF4J_CPUS` / `RDF4J_HEAP_MAX` does not speed those up. Raising nginx workers without `DRUPAL_CPUS` / `PHP_FPM_MAX_CHILDREN` does not speed Drupal up. SPARQL can approach 1G per PHP child, so keep `PHP_FPM_MAX_CHILDREN` in line with `DRUPAL_MEMORY`. Recreate the service after changing these (`docker compose up -d`).

Development enables OPcache with timestamp checks so bind-mounted WissKI still live-reloads. Xdebug stays in trigger mode; set `XDEBUG_MODE=off` in `.env` (and recreate Drupal) if you are not debugging — the extension still costs CPU while `mode=debug`.

Apple Silicon: append `docker-compose.apple-silicon.yml` to `COMPOSE_FILE` in `.env`. Local Drupal image build: append `docker-compose.local-build.yml`. WissKI Data Importer UI: append `docker-compose.importer.yml` (before `docker-compose.proxy.yml`) and `git submodule update --init wisski_data_importer`. Machine-local tweaks: copy `docker-compose.override.yml.example` to `docker-compose.override.yml` (gitignored) and append that file last.

### Attach Cursor / VS Code into Drupal

For IDE attach into the `drupal` container (persisted remote server, personal container-only settings, in-container Xdebug), use the override example. Shared WissKI workspace VS Code files live in [`.container-dev/wisski-vscode/`](.container-dev/wisski-vscode/). Keep personal files (`cursor/`, `wisski/`, Machine settings) gitignored under `/.container-dev/`.

The development image runs nginx/PHP-FPM as root/`www-data` and the attached IDE as **`developer`** (host UID, in the `www-data` group, write access under `/opt/drupal`, no sudo). That is why `~/.ssh` can be bind-mounted directly — OpenSSH requires the files to be owned by the user running `ssh`.

1. `cp docker-compose.override.yml.example docker-compose.override.yml`
2. Append `:docker-compose.override.yml` to `COMPOSE_FILE` in `.env`
3. If your host UID is not 1000, set `DEV_UID` / `DEV_GID` in `.env` (and rebuild locally so the image user matches)
4. `docker compose up -d`
5. Optional: add personal files under `/.container-dev/` (`cursor/`, Machine settings, a WissKI clone) and uncomment those mounts in `docker-compose.override.yml`. For git SSH remotes, uncomment the `~/.ssh` (or `SSH_HOST_PATH`) mount onto `/home/developer/.ssh`. Recreate Drupal after a development image that includes `openssh-client` and the `developer` user (local rebuild or a newer GHCR pull).
6. If you bind personal Machine `settings.json` files, create their parent dirs once:

```bash
docker compose exec -u developer drupal mkdir -p \
  /home/developer/.cursor-server/data/Machine \
  /home/developer/.vscode-server/data/Machine
```

7. If those file mounts were added before the dirs existed: `docker compose up -d --force-recreate drupal`
8. Attach Cursor/VS Code to the `drupal` service as user **`developer`** (the development compose file sets `remoteUser`)
9. Open `/opt/drupal/web/modules/contrib/wisski`
10. Start **Listen for Xdebug (in-container)**
11. Trigger with `XDEBUG_TRIGGER=1` / a browser helper; for Drush: `XDEBUG_TRIGGER=1 drush --xdebug …`

Optional live edit of a host WissKI clone: set `WISSKI_HOST_PATH` and uncomment that mount in the override (one module only — do not mount `vendor` or all of `contrib`). Development Xdebug is baked into the image (`127.0.0.1:9003`, trigger mode) for an IDE attached into `drupal`.

Per-developer (untracked) IDE customization:

- Shared workspace config is [`.container-dev/wisski-vscode/`](.container-dev/wisski-vscode/) (`settings.json`, `launch.json`, `extensions.json`), mounted onto `/opt/drupal/web/modules/contrib/wisski/.vscode`.
- Personal files stay gitignored under `/.container-dev/` (`cursor/`, `wisski/`, `vscode-machine-settings.json`). The override example has opt-in mounts for those, plus an optional host SSH key bind (`~/.ssh` or `.container-dev/ssh/` → `/home/developer/.ssh`).
- VS Code extensions themselves stay untracked in the persisted remote server volume.
- If you do not bind personal Machine settings files, edit remote settings directly in the attached container; they still persist in the named volumes and stay out of git.
- The local image build uses `./drupal` as its Docker build context, so repo-root `/.container-dev/` content is not copied into the image.

## Access

Caddy listens on `HTTP_PORT` (default 80) and routes by `Host`. Browsers resolve `*.localhost` to `127.0.0.1` (no `/etc/hosts`). If `HTTP_PORT` is not 80, add `:<port>` to every URL (e.g. `http://wisski.localhost:3600`). `localhost` and `127.0.0.1` still serve the public site.

| What | URL (defaults) |
| --- | --- |
| Site (Drupal in development, Varnish in production) | http://wisski.localhost (`SITE_HOST`) or http://localhost |
| Drupal (bypass Varnish) | http://drupal.wisski.localhost (`DRUPAL_HOST`) |
| OpenGDB / Django admin | http://gdb.wisski.localhost (`GDB_HOST`) |
| pgAdmin | http://dbms.wisski.localhost (`PGADMIN_HOST`, profile `tools`) |
| Solr (optional `solr` profile) | http://search.wisski.localhost (`SOLR_HOST`) |
| Data importer (optional `docker-compose.importer.yml`) | http://import.wisski.localhost (`IMPORTER_HOST`) |
| Drupal login | `DRUPAL_USER` / `DRUPAL_PASSWORD` |

Without `docker-compose.proxy.yml`, services keep the old host ports (`HTTP_PORT`, `PUBLIC_PORT`, `PGADMIN_PORT`, `SOLR_PORT`, production `DRUPAL_DIRECT_PORT`).

OpenGDB login is `DJANGO_SUPERUSER_NAME` / `DJANGO_SUPERUSER_PASSWORD`. On first install the Drupal entrypoint creates the `default` repository through OpenGDB (`POST /rest/repositories`) and fails if SPARQL does not return HTTP 200.

Drupal SPARQL talks to **authproxy**, not to the OpenGDB `nginx` service and not to RDF4J:

| Path | URL |
| --- | --- |
| Browser / Django admin | http://gdb.wisski.localhost (`GDB_HOST`) → OpenGDB nginx → authproxy |
| Drupal SPARQL (internal) | `http://authproxy:8000/repositories/default` |
| Raw RDF4J (do not use from Drupal) | `http://rdf4j:8080/rdf4j-server/repositories/default` |

Hitting RDF4J directly skips OpenGDB login and repository ACLs. `nginx` in this stack is OpenGDB’s reverse proxy for port 8080; it is not Drupal’s web server.

### Django admin, users, and SPARQL tokens

OpenGDB’s Django admin is [http://gdb.wisski.localhost/admin](http://gdb.wisski.localhost/admin) (`GDB_HOST`). Log in with `DJANGO_SUPERUSER_NAME` / `DJANGO_SUPERUSER_PASSWORD`.

By default Drupal SPARQL uses HTTP Basic with `TS_USERNAME` / `TS_PASSWORD` (same user as the Django superuser). OpenGDB also supports **token** auth, which avoids hashing the password on every SPARQL request. Use tokens over **HTTPS** in production ([OpenGDB note](https://github.com/FAU-CDI/open_gdb#token-authentication)).

1. **Optional dedicated user.** In Django admin → **Users**, add a user and give it rights on the `default` repository (RDF4J options / permissions). Or keep using the superuser.
2. **Get a token** (form fields, not JSON):

```bash
curl -sS -X POST "http://gdb.wisski.localhost/api-token-auth/" \
  -d username=YOUR_USER -d password=YOUR_PASSWORD
# {"token":"..."}
```

The same token is listed in Django admin under **Auth Token → Tokens**.

3. **Fresh install.** Set `TS_TOKEN` in `.env` **before** the first `docker compose up`. The entrypoint then creates the WissKI SALZ adapter with token auth (`TS_USERNAME` / `TS_PASSWORD` can stay empty). Changing `TS_TOKEN` later does **not** rewrite an existing adapter.
4. **Existing site.** Drupal → **Configuration → WissKI SALZ → Adapters** → Default (`/admin/config/wisski_salz/adapter/default/edit`) → enable token authentication, paste the token, save, then `docker compose exec drupal drush cr`.

If Drupal SPARQL fails after recreating authproxy, wait until `docker compose ps authproxy` is healthy and retry. On every boot the entrypoint rewrites the Default SALZ adapter read/write URLs from `TS_READ_URL` / `TS_WRITE_URL`; it does not rewrite the stored token or password. OpenGDB’s public UI (`GDB_HOST`) still goes through nginx; a 502 there usually means nginx still has a stale authproxy IP — `docker compose up -d --force-recreate nginx`.

## Layout

```
docker-compose.yml                      # default stack, include OpenGDB
docker-compose.development.yml          # Drupal + Xdebug (Caddy is the public HTTP entry)
docker-compose.production.yml           # Varnish as site upstream
docker-compose.proxy.yml                # Caddy subdomains on HTTP_PORT (in presets)
docker-compose.importer.yml             # optional: WissKI Data Importer UI (append)
docker-compose.local-build.yml          # optional: build Drupal locally (append)
docker-compose.apple-silicon.yml        # optional: amd64 via Rosetta (append)
docker-compose.override.yml.example     # template for machine-local overlay
env/development.env                     # copy to .env for development
env/production.env                      # copy to .env for production
drupal/                                 # PHP 8.5 FPM image (Dockerfile, entrypoint, PHP/Nginx)
opengdb/                                # git submodule (FAU-CDI/open_gdb)
wisski_data_importer/                   # git submodule (optional importer UI)
config/caddy/Caddyfile                  # Caddy Host routes
config/postgres/                        # Postgres init (pg_trgm)
config/varnish/default.vcl              # Varnish (production profile)
config/pgadmin/                         # pgAdmin servers.json (filled from DB_* on start)
config/opengdb/                         # RDF4J entrypoint, nginx DNS TTL
config/drupal/                          # example composer.local.json
.container-dev/wisski-vscode/           # shared in-container VS Code workspace files
drupal/config/                          # PHP, Nginx, Redis baked into the image
```

`.env` sets `COMPOSE_FILE` and `MODE`. With `COMPOSE_FILE` set, Compose loads **exactly** those files (no implicit `docker-compose.override.yml` merge). The presets are:

| Preset | `COMPOSE_FILE` |
| --- | --- |
| Development | `docker-compose.yml:docker-compose.development.yml:docker-compose.proxy.yml` |
| Production | `docker-compose.yml:docker-compose.production.yml:docker-compose.proxy.yml` |

Optional files are **not** in the presets. Append them in `.env` when needed, last file wins:

```bash
# Local image build (uses WISSKI_PACKAGES_VERSION / WISSKI_PACKAGES_LINE, currently 3.7.0 / 3.x)
COMPOSE_FILE=docker-compose.yml:docker-compose.development.yml:docker-compose.proxy.yml:docker-compose.local-build.yml

# WissKI Data Importer UI (init submodule first)
COMPOSE_FILE=docker-compose.yml:docker-compose.development.yml:docker-compose.importer.yml:docker-compose.proxy.yml

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

## WissKI Data Importer

Optional UI for CSV → Pathbuilder → WissKI import. It is a **separate app** (own Postgres and Redis), not a Drupal module.

```bash
git submodule update --init wisski_data_importer
# Append docker-compose.importer.yml to COMPOSE_FILE (before docker-compose.proxy.yml)
# Set WISSKI_DATA_IMPORTER_AUTH_* and WISSKI_DATA_IMPORTER_DJANGO_SECRET_KEY in .env
docker compose up -d --build wisski-data-importer-web wisski-data-importer-postgres wisski-data-importer-redis
```

Open http://import.wisski.localhost (`IMPORTER_HOST`). After login, in **Settings** use Docker DNS:

| Setting | URL |
| --- | --- |
| WissKI API | `http://drupal` |
| SPARQL | `http://authproxy:8000/repositories/default` |

If `HTTP_PORT` is not 80, add that port to `WISSKI_DATA_IMPORTER_CSRF_TRUSTED_ORIGINS` (e.g. `http://import.wisski.localhost:3600`).

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
