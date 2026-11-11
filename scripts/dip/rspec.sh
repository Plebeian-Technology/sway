#!/usr/bin/env bash
# @lat: [[error-reporting-in-tests#Where a browser's error reports go during a spec run]]
#
# Runs on the HOST, not in a service: compose's `environment:` beats `env_file:`,
# so the addresses must be set in the shell that calls `docker compose`.
#
# Off for one run: RUSTRAK_DSN= VITE_RUSTRAK_DSN= dip run rspec

set -eu

# dip appends arguments, and the container's command is fixed in compose, so
# they cannot reach rspec. Refuse rather than test everything silently.
if [ "$#" -gt 0 ]; then
    echo "dip run rspec takes no arguments — it runs the whole suite." >&2
    echo "For one file or one example, use:" >&2
    echo "    dip run bundle exec rspec $*" >&2
    exit 64
fi

scripts/dip/secrets-root.sh

# Compose interpolates the WHOLE file before it picks a service, so variables
# belonging to services this script never starts — the preview app and the two
# Cloudflare tunnels — print an "is not set" warning on every run. Resolving
# them to empty is what dev.sh already does for the tunnel it skips. Empty is
# safe for the master key: Rails reads that one with .presence and falls back
# to config/master.key, which is how the container gets it either way.
export CLOUDFLARED_DEV_TOKEN="${CLOUDFLARED_DEV_TOKEN:-}"
export CLOUDFLARED_PREVIEW_TOKEN="${CLOUDFLARED_PREVIEW_TOKEN:-}"
export RAILS_MASTER_KEY="${RAILS_MASTER_KEY:-}"

. scripts/dip/rustrak.sh
sway_rustrak_session_key
sway_rustrak_superuser
sway_rustrak_start

# Both addresses name rustrak:8080. Chromium runs in the container too, so
# localhost there would be the container itself and every report is refused.
: "${RUSTRAK_DSN=$(sway_rustrak_container_dsn)}"
: "${VITE_RUSTRAK_DSN=$(sway_rustrak_container_dsn)}"
export RUSTRAK_DSN="${RUSTRAK_DSN:-}"
export VITE_RUSTRAK_DSN="${VITE_RUSTRAK_DSN:-}"

if [ -n "$RUSTRAK_DSN" ]; then
    echo "rspec.sh: application errors go to the collector at http://localhost:${RUSTRAK_PORT:-8482}." >&2
else
    echo "rspec.sh: no collector address, so application errors are not recorded." >&2
fi

# @lat: [[testing-the-toolchain#Cleanup has to survive an interrupt]]
RUN_ID="$$-$(date +%s)"
container="sway-rspec-$RUN_ID"

# This run's own frontend build directory, the same shape verify.sh gives each
# of its runs. Vite empties its output directory before it builds, and
# with this unset that directory is public/vite-test itself — the PARENT of
# every verify run's vite-test/run-<id>. One vite_test volume is shared by every
# checkout, so without this a plain `dip run rspec` deleted a running
# `dip run verify`'s bundle and left its browser lane reading a gone manifest.
SWAY_VITE_BUILD_DIR="vite-test/run-$RUN_ID"

# --rm removes the container only when the container itself exits. A killed
# client leaves it running, still holding the test database.
cleanup() {
    status=$?
    trap - EXIT INT TERM
    docker rm -f "$container" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT INT TERM

# Build directories left behind by runs that were killed. They live inside the
# vite_test volume, so only a container can reach them, and this run's own is
# never a candidate: 1440 minutes is a day, far longer than any suite run.
# Swept here as well as in verify.sh because a machine may only ever run this.
docker compose -f .dockerdev/compose.yml -p sway run --rm --no-deps rspec \
    find /app/public/vite-test -maxdepth 1 -name "run-*" -type d -mmin +1440 -exec rm -rf {} + \
    >/dev/null 2>&1 || true

# @lat: [[testing-the-toolchain#Cleanup has to survive an interrupt]]
docker compose -f .dockerdev/compose.yml -p sway run --rm --name "$container" \
    -e SWAY_VITE_BUILD_DIR="$SWAY_VITE_BUILD_DIR" \
    rspec &
wait $!
