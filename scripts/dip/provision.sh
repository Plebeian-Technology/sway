#!/usr/bin/env bash

echo "provision.sh: Build and set up the dip environment for development and testing. This is invoked from dip.yml's provision: task. Env vars (RAILS_ENV, PORT, etc.) come from dip.yml's environment: block."

set -eu

if [ ! -f config/master.key ]; then
    echo "config/master.key is required to build the production preview image" >&2
    exit 1
fi

# A worktree reads it from the main checkout (scripts/dip/secrets-root.sh).
deploy_config="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/deploy/config/sway.env"
if [ ! -f "$deploy_config" ]; then
    echo "$deploy_config is missing. It holds this installation's own values and is never committed." >&2
    echo "Copy the template, then re-run: cp deploy/config/sway.env.example deploy/config/sway.env" >&2
    exit 1
fi

echo "provision.sh -> export RAILS_MASTER_KEY, CLOUDFLARED_DEV_TOKEN, and CLOUDFLARED_PREVIEW_TOKEN from config files"
export RAILS_MASTER_KEY="$(cat config/master.key)"
export CLOUDFLARED_DEV_TOKEN=""
export CLOUDFLARED_PREVIEW_TOKEN=""

# Bootstrap required compose environment files if not already present
if [ ! -f .env.development ] && [ -f .env.development.example ]; then
    echo "provision.sh: Initializing .env.development from template"
    cp .env.development.example .env.development
fi

if [ ! -f .env.test ] && [ -f .env.test.example ]; then
    echo "provision.sh: Initializing .env.test from template"
    cp .env.test.example .env.test
fi

if [ ! -f .env.preview ] && [ -f .env.preview.example ]; then
    echo "provision.sh: Initializing .env.preview from template"
    cp .env.preview.example .env.preview
fi

# We need the `|| true` part because some docker-compose versions
# cannot down a non-existent container without an error,
# see https://github.com/docker/compose/issues/9426
#
# Stop containers but DO NOT pass --volumes — that would also nuke
# sway_bundle and sway_node_modules, which take many minutes to rebuild.
# Instead, drop the volumes we actually want fresh (DBs, caches, assets)
# explicitly and leave bundle / node_modules intact.
dip compose down || true

VOLUMES_TO_RESET=(
    # sway_storage is kept; its databases are dropped below.
    sway_history
    sway_rails_cache
    sway_assets
    sway_vite_build
    sway_vite_test
    # sway_postgres_data
)
for vol in "${VOLUMES_TO_RESET[@]}"; do
    docker volume rm "$vol" >/dev/null 2>&1 || true
done

echo "dip build"
dip build

echo "Remove db/schema.rb."
rm -r db/schema.rb || true

# WEBAUTHN_* match the preview service in .dockerdev/compose.yml.
preview_env="RAILS_ENV=production SECRET_KEY_BASE=preview-secret-key-base DISABLE_DATABASE_ENVIRONMENT_CHECK=1 SWAY_DATABASE_NAME=storage/preview.sqlite3 SWAY_QUEUE_DATABASE_NAME=storage/preview_queue.sqlite3 SWAY_CABLE_DATABASE_NAME=storage/preview_cable.sqlite3 SWAY_CACHE_DATABASE_NAME=storage/preview_cache.sqlite3 WEBAUTHN_RP_ID=localhost WEBAUTHN_ALLOWED_ORIGINS=https://localhost:3334,http://localhost:3334"

# @lat: [[development-container-settings#Why provision drops the databases through Rails]]
echo "Drop the development and test databases with dip bash -c 'RAILS_ENV=development bin/rails db:drop'"
dip bash -c "RAILS_MASTER_KEY=$RAILS_MASTER_KEY RAILS_ENV=development bin/rails db:drop"

echo "Drop the preview databases with dip bash -c 'RAILS_ENV=production... bin/rails db:drop'"
dip bash -c "RAILS_MASTER_KEY=$RAILS_MASTER_KEY $preview_env bin/rails db:drop"

# Bill seeding is NOT part of bin/setup — it's opt-in via
# `dip run rails sway:seed_bills`. Provision only sets up locales,
# legislators, and admin user.
echo "Setup development with dip bash -c 'RAILS_ENV=development bin/setup'"
dip bash -c "RAILS_MASTER_KEY=$RAILS_MASTER_KEY RAILS_ENV=development bin/setup"

echo "Setup test with dip bash -c 'RAILS_ENV=test bin/setup'"
dip bash -c "RAILS_MASTER_KEY=$RAILS_MASTER_KEY RAILS_ENV=test bin/setup"

echo "Setup development with dip bash -c 'RAILS_ENV=development bin/rake sway:deploy'"
dip bash -c "RAILS_MASTER_KEY=$RAILS_MASTER_KEY RAILS_ENV=development bin/rake sway:deploy"

echo "Setup preview with dip bash -c 'RAILS_ENV=production...'"
dip bash -c "RAILS_MASTER_KEY=$RAILS_MASTER_KEY $preview_env bin/rails db:prepare db:schema:load:queue"

echo "Ensure mkcert certs exist for caddy and cloudflared"
./scripts/dip/ensure-mkcert-certs.sh
