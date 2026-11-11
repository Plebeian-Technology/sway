#!/usr/bin/env bash
# Start up the development stack (rails, vite, caddy, background workers) via dip.
# Invoked from dip.yml `dev:` task. Env vars (RAILS_ENV, PORT, etc.) come from
# dip.yml's environment: block.

set -eu

if [ ! -f config/master.key ]; then
    echo "config/master.key is required to build the production preview image" >&2
    exit 1
fi
export RAILS_MASTER_KEY="$(cat config/master.key)"
export CLOUDFLARED_PREVIEW_TOKEN=""

# @lat: [[deploy-values-boot-check#Keeping one installation's values out of the tracked repository]]
if [ -f deploy/config/load.sh ]; then
    . deploy/config/load.sh
    sway_load_config || true
fi

# --- Cloudflare tunnel (optional) --------------------------------------------
# Token precedence: an exported CLOUDFLARED_DEV_TOKEN, then the gitignored
# config/cloudflared.key. Bring your own tunnel by writing your token to that
# file or exporting the variable. Without a token cloudflared would crash-loop
# under `restart: unless-stopped`, so drop the service rather than start it
# empty; everything else is still served through Caddy.
# @lat: [[browser-error-reporting#Development reports stay on this machine]]
services=(vite caddy web jobs rustrak rustrak_ui)
if [ -z "${CLOUDFLARED_DEV_TOKEN:-}" ] && [ -f config/cloudflared.key ]; then
    CLOUDFLARED_DEV_TOKEN="$(cat config/cloudflared.key)"
fi
export CLOUDFLARED_DEV_TOKEN="${CLOUDFLARED_DEV_TOKEN:-}"

if [ -n "$CLOUDFLARED_DEV_TOKEN" ]; then
    services+=(dev_cloudflared)
    if [ -z "${DEV_TUNNEL_HOST:-}" ]; then
        echo "dev.sh: a tunnel token is set but DEV_TUNNEL_HOST is not." >&2
        echo "        Set DEV_TUNNEL_HOST to the tunnel's public hostname (see deploy/config/sway.env.example)," >&2
        echo "        or Rails will refuse requests that arrive through the tunnel." >&2
    fi
else
    echo "dev.sh: no Cloudflare tunnel token — starting without the tunnel." >&2
    echo "        The app is still served at https://localhost:3333 via Caddy." >&2
fi

# Collector setup is shared with scripts/dip/rspec.sh.
. scripts/dip/rustrak.sh
sway_rustrak_session_key
sway_rustrak_superuser

# --- Public hostname ----------------------------------------------------------
# One value drives everything host-coupled: Rails host authorization
# (config.hosts), the WebAuthn relying-party ID, and the allowed passkey
# origins. It defaults to localhost. Set DEV_TUNNEL_HOST to your tunnel's
# public hostname; the RP ID must equal the host the browser is on or passkey
# ceremonies fail.
export DEV_TUNNEL_HOST="${DEV_TUNNEL_HOST:-localhost}"
export WEBAUTHN_RP_ID="${WEBAUTHN_RP_ID:-$DEV_TUNNEL_HOST}"
# SWAY_DEV_BROWSER_HOST and SWAY_DEV_BROWSER_PORT are deliberately NOT derived
# from DEV_TUNNEL_HOST, and that is the whole point of this comment.
#
# rails_vite writes an absolute address into every script tag, built from that
# host and port. So the pair has to be the origin the BROWSER is on, not the
# origin the app can also be reached at. Those are different questions, and
# DEV_TUNNEL_HOST answers the second one.
#
# Deriving them from DEV_TUNNEL_HOST broke development: with a tunnel host set,
# a person browsing https://localhost:3333 got tags pointing at the tunnel host
# and every module was refused as cross-origin. One absolute address cannot
# serve two origins.
#
# Left unset, vite.config.ts defaults to localhost:3333, which is where Caddy
# serves this stack. To work through the tunnel instead — a phone, another
# machine — set both explicitly and browse that host only:
#
#   SWAY_DEV_BROWSER_HOST=<your tunnel host> SWAY_DEV_BROWSER_PORT=443 dip dev

localhost_origins="https://localhost:3333,http://localhost:3333,https://localhost"
if [ "$DEV_TUNNEL_HOST" = "localhost" ]; then
    default_origins="$localhost_origins"
else
    default_origins="https://$DEV_TUNNEL_HOST,$localhost_origins"
fi
export WEBAUTHN_ALLOWED_ORIGINS="${WEBAUTHN_ALLOWED_ORIGINS:-$default_origins}"

# --- Audio bucket -------------------------------------------------------------
export VITE_SWAY_ASSETS_BUCKET="${VITE_SWAY_ASSETS_BUCKET:-${SWAY_GCS_BUCKET_ASSETS:-}}"

dip down

if printf '%s\n' "${services[@]}" | grep -qx rustrak; then
    sway_rustrak_start
fi

# In development the browser is on the host and Rails is in a container, so the
# two take different routes. An address already set WINS, empty included, which
# is the off switch: RUSTRAK_DSN= VITE_RUSTRAK_DSN= dip run dev
: "${VITE_RUSTRAK_DSN=$(sway_rustrak_host_dsn)}"
: "${RUSTRAK_DSN=$(sway_rustrak_container_dsn)}"
export VITE_RUSTRAK_DSN="${VITE_RUSTRAK_DSN:-}"
export RUSTRAK_DSN="${RUSTRAK_DSN:-}"

# @lat: [[run-the-stack#If edits stop reaching the browser]]
vite_project="$(awk '/^[[:space:]]*project_name:/ {print $2; exit}' dip.yml 2>/dev/null || true)"
vite_container="${vite_project:-sway}-vite-1"

announce_vite_unhealthy() {
    while read -r action; do
        case "$action" in
        *unhealthy*)
            echo "dev.sh: the Vite hot-reload client at /@vite/client is not answering." >&2
            echo "        Pages still load; edits will not reach the browser." >&2
            echo "        Run: docker restart $vite_container" >&2
            ;;
        esac
    done
}

docker events --filter event=health_status --filter "container=$vite_container" --format '{{.Action}}' \
    > >(announce_vite_unhealthy) &
vite_watcher_pid=$!
trap 'kill "$vite_watcher_pid" 2>/dev/null || true' EXIT

dip up "${services[@]}"
