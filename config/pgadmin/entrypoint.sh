#!/bin/sh
# Fill servers.json / pgpass from DB_* and re-import on every start.
# pgAdmin 8 only loads servers.json when the config DB is first created.
set -eu

export DB_HOST="${DB_HOST:-postgres}"
export DB_PORT="${DB_PORT:-5432}"
export DB_NAME="${DB_NAME:-wisski}"
export DB_USER="${DB_USER:-wisski}"
export DB_PASSWORD="${DB_PASSWORD:-wisski}"

/venv/bin/python3 - <<'PY'
import json
import os
import pathlib
import re

def subst_str(value):
  def repl(match):
    key = match.group(1)
    if key not in os.environ:
      raise SystemExit("missing environment variable %s" % key)
    return os.environ[key]
  return re.sub(r"\$\{([A-Z_][A-Z0-9_]*)\}", repl, value)

def subst(obj):
  if isinstance(obj, dict):
    return {key: subst(value) for key, value in obj.items()}
  if isinstance(obj, list):
    return [subst(value) for value in obj]
  if isinstance(obj, str):
    return subst_str(obj)
  return obj

def pgpass_escape(value: str) -> str:
  return value.replace("\\", "\\\\").replace(":", "\\:")

data = subst(json.loads(pathlib.Path("/config/servers.json").read_text()))
for server in data.get("Servers", {}).values():
  if "Port" in server:
    server["Port"] = int(server["Port"])

pathlib.Path("/tmp/servers.json").write_text(json.dumps(data, indent=2) + "\n")

pgpass = ":".join([
  pgpass_escape(os.environ["DB_HOST"]),
  pgpass_escape(os.environ["DB_PORT"]),
  "*",
  pgpass_escape(os.environ["DB_USER"]),
  pgpass_escape(os.environ["DB_PASSWORD"]),
]) + "\n"
pgpass_path = pathlib.Path("/tmp/pgpass")
pgpass_path.write_text(pgpass)
pgpass_path.chmod(0o600)
PY

export PGADMIN_SERVER_JSON_FILE=/tmp/servers.json
export PGPASS_FILE=/tmp/pgpass

install_pgpass() {
  dest="/var/lib/pgadmin/.pgpass"
  if [ "${PGADMIN_CONFIG_SERVER_MODE}" != "False" ]; then
    user_dir="$(printf '%s' "${PGADMIN_DEFAULT_EMAIL}" | sed 's/@/_/g')"
    mkdir -p "/var/lib/pgadmin/storage/${user_dir}"
    dest="/var/lib/pgadmin/storage/${user_dir}/.pgpass"
  fi
  cp /tmp/pgpass "${dest}"
  chmod 600 "${dest}"
  if [ "$(id -u)" = "0" ]; then
    chown 5050:5050 "${dest}" 2>/dev/null || true
  fi
}

# Image 8 skips load-servers after the first init; re-apply when .env changes.
if [ -f /var/lib/pgadmin/pgadmin4.db ]; then
  if [ "${PGADMIN_CONFIG_SERVER_MODE}" = "False" ]; then
    /venv/bin/python3 /pgadmin4/setup.py load-servers "${PGADMIN_SERVER_JSON_FILE}" --replace
  else
    /venv/bin/python3 /pgadmin4/setup.py load-servers "${PGADMIN_SERVER_JSON_FILE}" --replace --user "${PGADMIN_DEFAULT_EMAIL}"
  fi
  install_pgpass
fi

exec /entrypoint.sh
