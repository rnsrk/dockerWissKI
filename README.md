# Docker WissKI

Standalone WissKI stack with a PHP 8.5 FPM Drupal image, PostgreSQL 17, [OpenGDB](https://github.com/FAU-CDI/open_gdb) (RDF4J 6), Redis 8, Varnish 9, Caddy, and pgAdmin. Solr 10 and the [WissKI Data Importer](https://git.nasarek.dev/rnsrk/wisski_data_importer) UI are optional.

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
| Lint and test tools | phpcs, phpstan, `drupal/core-dev`, cspell/eslint/stylelint (baked in) | not included |
| WissKI module | git clone on volume `wisski-module` | image codebase |
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

### Shell as developer

```bash
docker compose exec -u developer drupal bash
```

Omit `-u developer` to run as root. PHP-FPM stays `www-data`.

In development, `/opt/drupal` stays `www-data`-owned with group-write + setgid so `developer` (in `www-data`) can edit the tree. `settings.php` stays read-only (444); `sites/default` itself is writable (775) so you can add `settings.local.php`. Production still locks `sites/default` to 555.

### WissKI clone (development)

In development, `web/modules/contrib/wisski` is a git clone on the named volume `wisski-module`. Branches, remotes, `.git/config`, `vendor/`, and `node_modules/` survive container recreation, image pulls, and rebuilds. Docker fills the empty volume from the image once. Later image updates do not touch it, so update the clone with git (`git fetch`, `git rebase`, …). To start over from the image: `docker compose down`, `docker volume rm dockerwisski_wisski-module`, `docker compose up -d`.

A host clone bind-mounted on the same path in `docker-compose.override.yml` replaces the volume (see `WISSKI_HOST_PATH`). If that host directory is empty, the entrypoint clones WissKI into it at the commit the image was built with.

The lint and test tools follow the Drupal GitLab CI layout. The PHP tools (WissKI `require-dev` plus `drupal/core-dev` at the installed core version, which brings `phpstan-phpunit`, `behat/mink`, and `prophecy-phpunit`) are in `/opt/drupal/vendor/bin`. `misc/scripts/*.sh` fall back to them through `PATH`. The JS tools are in the clone's `node_modules/`. The entrypoint runs `yarn install` when they are missing. Do not run `composer install` inside the clone: `drupal/potx` pulls a second `drupal/core` into the clone's `vendor/`, and PHPStan then aborts with `Cannot redeclare t()`. The entrypoint warns when it finds one.

### Attach Cursor / VS Code / Claude Code into Drupal

For IDE attach into the `drupal` container (persisted remote server, personal container-only settings, in-container Xdebug), use the override example. Shared WissKI workspace VS Code files live in [`.container-dev/wisski-vscode/`](.container-dev/wisski-vscode/). Keep personal files (`cursor/`, `claude/`, `wisski/`, Machine settings) gitignored under `/.container-dev/`.

The development image runs nginx/PHP-FPM as root/`www-data` and the attached IDE as **`developer`** (host UID, in the `www-data` group, write access under `/opt/drupal`, no sudo). That is why `~/.ssh` can be bind-mounted directly — OpenSSH requires the files to be owned by the user running `ssh`.

1. `cp docker-compose.override.yml.example docker-compose.override.yml`
2. Append `:docker-compose.override.yml` to `COMPOSE_FILE` in `.env`
3. If your host UID is not 1000, set `DEV_UID` / `DEV_GID` in `.env` (and rebuild locally so the image user matches)
4. `docker compose up -d`
5. Optional: add personal files under `/.container-dev/` (`cursor/`, `claude/`, Machine settings, a WissKI clone) and uncomment those mounts in `docker-compose.override.yml`. Cursor and Claude Code rules/skills/agents bind onto `/home/developer/.cursor` and `/home/developer/.claude` (Claude `settings.json` onto `~/.claude/settings.json`) so the WissKI clone stays clean. For git SSH remotes, uncomment the `~/.ssh` (or `SSH_HOST_PATH`) mount onto `/home/developer/.ssh`. Recreate Drupal after a development image that includes `openssh-client` and the `developer` user (local rebuild or a newer GHCR pull).
6. If you bind personal Machine `settings.json` files, create their parent dirs once:

```bash
docker compose exec -u developer drupal mkdir -p \
  /home/developer/.cursor-server/data/Machine \
  /home/developer/.vscode-server/data/Machine
```

7. If those file mounts were added before the dirs existed: `docker compose up -d --force-recreate drupal`
8. Attach Cursor / VS Code / Claude Code to the `drupal` service as user **`developer`** (the development compose file sets `remoteUser`)
9. Open `/opt/drupal/web/modules/contrib/wisski`
10. Start **Listen for Xdebug (in-container)**
11. Trigger with `XDEBUG_TRIGGER=1` / a browser helper; for Drush: `XDEBUG_TRIGGER=1 drush --xdebug …`

Optional host WissKI clone instead of the `wisski-module` volume: set `WISSKI_HOST_PATH` and uncomment that mount in the override (one module only — do not mount `vendor` or all of `contrib`). `DEV_UID` / `DEV_GID` must match the host owner of the clone. Development Xdebug is baked into the image (`127.0.0.1:9003`, trigger mode) for an IDE attached into `drupal`.

Per-developer (untracked) IDE customization:

- Shared workspace config is [`.container-dev/wisski-vscode/`](.container-dev/wisski-vscode/) (`settings.json`, `launch.json`, `extensions.json`), mounted onto `/opt/drupal/web/modules/contrib/wisski/.vscode`.
- Personal files stay gitignored under `/.container-dev/` (`cursor/`, `claude/`, `wisski/`, `vscode-machine-settings.json`). The override example has opt-in mounts for those, plus an optional host SSH key bind (`~/.ssh` or `.container-dev/ssh/` → `/home/developer/.ssh`). Cursor and Claude Code bind `rules/`, `skills/`, and `agents/` onto `/home/developer/.cursor` and `/home/developer/.claude`. Claude Code `settings.json` binds onto `/home/developer/.claude/settings.json`. Do not bind `.claude/` into the WissKI module tree.
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

By default Drupal SPARQL uses HTTP Basic with `TS_USERNAME` / `TS_PASSWORD` (same user as the Django superuser). Bootstrap never reads a SPARQL token from `.env`. Optional **token** auth lives only in OpenGDB (Django admin → Auth Token) and in the WissKI SALZ adapter UI — paste it there if you want it, over **HTTPS** in production ([OpenGDB note](https://github.com/FAU-CDI/open_gdb#token-authentication)).

1. **Optional dedicated user.** In Django admin → **Users**, add a user and give it rights on the `default` repository (RDF4J options / permissions). Or keep using the superuser.
2. **Get a token** (form fields, not JSON):

```bash
curl -sS -X POST "http://gdb.wisski.localhost/api-token-auth/" \
  -d username=YOUR_USER -d password=YOUR_PASSWORD
# {"token":"..."}
```

The same token is listed in Django admin under **Auth Token → Tokens**.

3. **Existing site.** Drupal → **Configuration → WissKI SALZ → Adapters** → Default (`/admin/config/wisski_salz/adapter/default/edit`) → enable token authentication, paste the token, save, then `docker compose exec drupal drush cr`.

If Drupal SPARQL fails after recreating authproxy, wait until `docker compose ps authproxy` is healthy and retry. On every boot the entrypoint rewrites the Default SALZ adapter read/write URLs from `TS_READ_URL` / `TS_WRITE_URL`; it does not rewrite the stored password. OpenGDB’s public UI (`GDB_HOST`) still goes through nginx; a 502 there usually means nginx still has a stale authproxy IP — `docker compose up -d --force-recreate nginx`.

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
patches/opengdb/                        # patch for the OpenGDB authproxy, applied at build time
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
# Local image build (uses WISSKI_PACKAGES_VERSION / WISSKI_PACKAGES_LINE, development preset 4.3.0 / 4.x)
COMPOSE_FILE=docker-compose.yml:docker-compose.development.yml:docker-compose.proxy.yml:docker-compose.local-build.yml

# WissKI Data Importer UI (init submodule first)
COMPOSE_FILE=docker-compose.yml:docker-compose.development.yml:docker-compose.importer.yml:docker-compose.proxy.yml

# Then: docker compose build drupal
# or:   docker compose up -d --build
```

`docker-compose.override.yml` is gitignored. Copy the example and append it last for bind-mounts, extra ports, or other machine-only changes.

The development image installs WissKI’s PHP lint tools from the module `require-dev` (WissKI 4.x; 3.x `scs_base` has none), `drupal/core-dev` at the installed core version, and the module's Yarn tools (`node_modules/`). Do not put those packages in `composer.local.json`.

## Updating OpenGDB

```bash
git submodule update --remote opengdb
```

Pin the new submodule commit in this repository when it works.

The authproxy is built from the unchanged submodule and then patched with the files in [`patches/opengdb/`](patches/opengdb/) (`docker compose build authproxy`). The patch stops a refused RDF4J `PUT` from deleting an existing repository; [its README](patches/opengdb/README.md) has the details and the text for the upstream pull request. If a submodule update makes the patch fail to apply, check whether upstream already contains the fix.

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
| WissKI lint and test tools (phpcs, phpstan, `drupal/core-dev`, cspell) | Development image | baked at build; do not put in `composer.local.json` |
| WissKI git clone (development) | volume `wisski-module` | seeded from the image once; update with git |
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
