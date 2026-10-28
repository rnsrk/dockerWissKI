# Attach Cursor / VS Code / Claude Code into Drupal

For IDE attach into the `drupal` container (persisted remote server, personal container-only settings, in-container Xdebug), use the override example (`docker-compose.override.yml.example` in the repository root). Shared WissKI workspace VS Code files live in [`.container-dev/wisski-vscode/`](../.container-dev/wisski-vscode/). Keep personal files (`cursor/`, `claude/`, `wisski/`, Machine settings) gitignored under `/.container-dev/`.

The development image runs nginx/PHP-FPM as root/`www-data` and the attached IDE as **`developer`** (host UID, in the `www-data` group, write access under `/opt/drupal`, no sudo). That is why `~/.ssh` can be bind-mounted directly — OpenSSH requires the files to be owned by the user running `ssh`.

1. `cp docker-compose.override.yml.example docker-compose.override.yml`
2. Append `:docker-compose.override.yml` to `COMPOSE_FILE` in `.env`
3. If your host UID is not 1000, set `DEV_UID` / `DEV_GID` in `.env` (the entrypoint adjusts the `developer` user to it on every start)
4. `docker compose up -d`
5. Optional: add personal files under `/.container-dev/` (`cursor/`, `claude/`, Machine settings, a WissKI clone) and uncomment those mounts in `docker-compose.override.yml`. Claude Code rules/skills/agents bind onto `/home/developer/.claude` (`settings.json` onto `~/.claude/settings.json`). Cursor rules bind into the WissKI clone's `.cursor/rules` (gitignored there), because Cursor loads `.mdc` rules only from the opened workspace; Cursor agents bind onto `/home/developer/.cursor/agents`, and Cursor reads skills from `~/.claude/skills`. For git SSH remotes, uncomment the `~/.ssh` (or `SSH_HOST_PATH`) mount onto `/home/developer/.ssh`. Recreate Drupal after a development image that includes `openssh-client` and the `developer` user (local rebuild or a newer GHCR pull).
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

- Shared workspace config is [`.container-dev/wisski-vscode/`](../.container-dev/wisski-vscode/) (`settings.json`, `launch.json`, `extensions.json`), mounted onto `/opt/drupal/web/modules/contrib/wisski/.vscode`.
- Personal files stay gitignored under `/.container-dev/` (`cursor/`, `claude/`, `wisski/`, `vscode-machine-settings.json`). The override example has opt-in mounts for those, plus an optional host SSH key bind (`~/.ssh` or `.container-dev/ssh/` → `/home/developer/.ssh`). Claude Code binds `rules/`, `skills/`, `agents/`, and `settings.json` onto `/home/developer/.claude`. Cursor binds `rules/` onto `/opt/drupal/web/modules/contrib/wisski/.cursor/rules` and `agents/` onto `/home/developer/.cursor/agents`; it reads skills from `~/.claude/skills`, so there is no Cursor copy. Do not bind `.claude/` into the WissKI module tree (it is not gitignored there).
- VS Code extensions themselves stay untracked in the persisted remote server volume.
- If you do not bind personal Machine settings files, edit remote settings directly in the attached container; they still persist in the named volumes and stay out of git.
- The local image build uses `./drupal` as its Docker build context, so repo-root `/.container-dev/` content is not copied into the image.
