#!/usr/bin/env python3
"""Shared helpers for the Sway production debugging toolkit.

These scripts run from the OPERATOR's workstation — never on the Pi and
never inside the Rails app. Everything Pi-side rides over SSH using the existing
Kamal deploy key (SWAY_SSH_KEY); Cloudflare and New Relic use read-only API
tokens. Nothing here is loaded by, or shipped with, the application.

Config comes from environment variables, optionally seeded by a local .env file
(see README.md). os.environ always wins over .env.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ENV_PATH = Path(__file__).resolve().parent / ".env"
# SSH writes the host key here (a repo-local path) because some sandboxes block
# writes to ~/.ssh/known_hosts. Lives under .secrets/ (gitignored).
KNOWN_HOSTS = str(Path(__file__).resolve().parent / ".secrets" / "known_hosts")


def load_env() -> None:
    """Minimal .env loader (no python-dotenv dependency). os.environ wins."""
    if not ENV_PATH.exists():
        return
    for raw in ENV_PATH.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


def env(key: str, default: str | None = None, *, required: bool = False) -> str:
    val = os.environ.get(key, default)
    if required and not val:
        sys.exit(
            f"[config] missing required env var {key} "
            f"(set it in ops/monitoring/.env — see README.md)"
        )
    return val or ""


def isfloat(s: str) -> bool:
    try:
        float(s)
        return True
    except (TypeError, ValueError):
        return False


# --------------------------------------------------------------------------
# Pi / SSH
# --------------------------------------------------------------------------

def pi_target() -> tuple[str, str, str]:
    """(ssh_key_path, user, host), read the same way the deploy reads them.

    Nothing is written down here. The address and login describe one person's
    network and this repository is public, so they come from the environment or
    from deploy/config/sway.env. A missing one raises rather than
    being guessed: a guessed address makes every probe fail in a way that reads
    like the machine being down.
    """
    values = deploy_config()
    missing = [
        name
        for name in ("SWAY_SSH_KEY", "SWAY_DEPLOY_USER", "SWAY_HOST")
        if not values.get(name)
    ]
    if missing:
        raise SystemExit(
            "Sway does not know these values: "
            + ", ".join(missing)
            + "\nSet them, or write deploy/config/sway.env "
            "(copy deploy/config/sway.env.example)."
        )

    return (
        os.path.expanduser(values["SWAY_SSH_KEY"]),
        values["SWAY_DEPLOY_USER"],
        values["SWAY_HOST"],
    )


def deploy_config() -> dict[str, str]:
    """Every deploy value, environment first then deploy/config/sway.env.

    Same order and same file as lib/sway_deploy_config.rb and
    deploy/config/load.sh. Kept short rather than shared, because this package
    is a handful of standalone scripts with no Ruby available.
    """
    root = Path(__file__).resolve().parent.parent.parent
    path = Path(os.environ.get("SWAY_DEPLOY_CONFIG_FILE") or root / "deploy" / "config" / "sway.env")

    values: dict[str, str] = {}
    if path.is_file():
        for line in path.read_text().splitlines():
            line = line.strip().removeprefix("export ")
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, _, value = line.partition("=")
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            values[name.strip()] = value

    # Anything already in the environment wins, exactly as elsewhere.
    values.update({k: v for k, v in os.environ.items() if v})
    return values


def ssh(remote_cmd: str, *, timeout: int = 30, check: bool = True) -> str:
    """Run a command on the Pi over SSH and return stdout.

    BatchMode=yes makes it fail fast instead of hanging on a password prompt.
    """
    key, user, host = pi_target()
    argv = [
        "ssh", "-i", key,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=8",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", f"UserKnownHostsFile={KNOWN_HOSTS}",
        f"{user}@{host}", remote_cmd,
    ]
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"ssh timed out after {timeout}s: {remote_cmd[:80]}")
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"ssh exit {proc.returncode}: {remote_cmd[:80]}\n{proc.stderr.strip()}"
        )
    return proc.stdout


def docker_container(name_or_image: str, override_env: str | None = None) -> str:
    """Resolve a running container by explicit override, or name/image match."""
    if override_env:
        override = env(override_env)
        if override:
            return override
    rows = ssh("docker ps --format '{{.Names}}\t{{.Image}}'").splitlines()
    for row in rows:
        parts = row.split("\t")
        name = parts[0].strip()
        image = parts[1] if len(parts) > 1 else ""
        if name_or_image in name or name_or_image in image:
            return name
    seen = ", ".join(r.split("\t")[0] for r in rows) or "(none running)"
    raise RuntimeError(
        f"no container matches '{name_or_image}'. Seen: {seen}. "
        f"Override via {override_env or 'env'}."
    )


def container_ip(name: str) -> str:
    out = ssh(
        "docker inspect -f "
        "'{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' " + name
    ).split()
    if not out:
        raise RuntimeError(f"no IP for container {name}")
    return out[0]


# --------------------------------------------------------------------------
# Pi-side SQLite (read-only, WAL-safe). Best-effort: callers tolerate failure.
# --------------------------------------------------------------------------

def storage_path() -> str:
    return deploy_config().get("SWAY_STORAGE_DIR") or env("PI_STORAGE_PATH", "")


def primary_db() -> str:
    return f"{storage_path()}/{env('PI_PRIMARY_DB', 'production.sqlite3')}"


def queue_db() -> str:
    return f"{storage_path()}/{env('PI_QUEUE_DB', 'production_queue.sqlite3')}"


def cable_db() -> str:
    return f"{storage_path()}/{env('PI_CABLE_DB', 'production_cable.sqlite3')}"


def sqlite_query(db_path: str, query: str, *, timeout: int = 12) -> str:
    """Read-only SQLite query against a file on the Pi host.

    Opens read-only so it can never disturb the app's writes. Returns '' on any
    error (missing sqlite3 CLI, perms, schema drift) so dashboards degrade to
    'n/a' rather than crashing.
    """
    remote = f"sqlite3 -readonly -noheader -separator '|' '{db_path}' \"{query}\" 2>/dev/null || true"
    try:
        return ssh(remote, timeout=timeout, check=False).strip()
    except RuntimeError:
        return ""


# --------------------------------------------------------------------------
# HTTP (stdlib only — no third-party dependency)
# --------------------------------------------------------------------------

def http_json(
    url: str, *, method: str = "GET", headers: dict | None = None,
    body: dict | None = None, timeout: int = 30,
) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    headers = dict(headers or {})
    if data is not None:
        headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        raise RuntimeError(f"HTTP {e.code} from {url}: {detail}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"connection error to {url}: {e.reason}")
