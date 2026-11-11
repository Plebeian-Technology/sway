#!/usr/bin/env bash
# Build and run the production-mode preview stack behind the Cloudflare tunnel.
# Invoked from dip.yml `preview:` task. Env vars (RAILS_ENV=production,
# PREVIEW_IMAGE, PREVIEW_DOCKERFILE, CLOUDFLARED_PREVIEW_TOKEN, etc.) come from
# dip.yml's environment: block.

set -eu

if [ ! -f config/master.key ]; then
    echo "config/master.key is required to build the production preview image" >&2
    exit 1
fi
export RAILS_MASTER_KEY="$(cat config/master.key)"

export $(grep -v '^#' .env.development | xargs)

# @lat: [[deploy-build-value-propagation#The fix]]
if [ -f deploy/config/load.sh ]; then
    . deploy/config/load.sh
    sway_load_config || true
fi

if [ -n "${PREVIEW_HOST:-}" ]; then
    export RAILS_ALLOWED_HOSTS="${RAILS_ALLOWED_HOSTS:+$RAILS_ALLOWED_HOSTS,}$PREVIEW_HOST"
fi

PREVIEW_BUILD_ARGS=""
for name in RAILS_ALLOWED_HOSTS SWAY_GCP_PROJECT_ID SWAY_GCS_BUCKET_ASSETS SWAY_GCS_BUCKET_DB SWAY_GCS_BUCKET_LEGISLATION SWAY_LITESTREAM_PATH; do
    eval "value=\${$name:-}"
    [ -n "$value" ] && PREVIEW_BUILD_ARGS="$PREVIEW_BUILD_ARGS --build-arg $name=$value"
done
# Vite fixes the assets bucket into the bundle, so it is a build setting too.
if [ -n "${SWAY_GCS_BUCKET_ASSETS:-}" ]; then
    PREVIEW_BUILD_ARGS="$PREVIEW_BUILD_ARGS --build-arg VITE_SWAY_ASSETS_BUCKET=$SWAY_GCS_BUCKET_ASSETS"
fi

docker rm -f "${PREVIEW_CONTAINER_NAME}" >/dev/null 2>&1 || true

if [ -n "${SENTRY_AUTH_TOKEN:-}" ]; then
    PREVIEW_SENTRY_SECRET="--secret id=SENTRY_AUTH_TOKEN,env=SENTRY_AUTH_TOKEN"
else
    PREVIEW_SENTRY_SECRET="--secret id=SENTRY_AUTH_TOKEN,src=/dev/null"
fi

DOCKER_BUILDKIT=1 docker buildx build \
    --load \
    --tag "${PREVIEW_IMAGE}" \
    --secret id=RAILS_MASTER_KEY,src=config/master.key \
    --secret id=VITE_GOOGLE_MAPS_API_KEY,env=VITE_GOOGLE_MAPS_API_KEY \
    ${PREVIEW_SENTRY_SECRET} \
    ${PREVIEW_BUILD_ARGS} \
    --file "${PREVIEW_DOCKERFILE}" \
    .

dip compose rm -fs preview preview_caddy preview_cloudflared >/dev/null 2>&1 || true

# @lat: [[auxiliary-databases#Why the queue database names a migrations path]]
dip bash -c 'RAILS_ENV=production SECRET_KEY_BASE=preview-secret-key-base RAILS_MASTER_KEY=$(cat config/master.key) DISABLE_DATABASE_ENVIRONMENT_CHECK=1 SWAY_DATABASE_NAME=storage/preview.sqlite3 SWAY_QUEUE_DATABASE_NAME=storage/preview_queue.sqlite3 SWAY_CABLE_DATABASE_NAME=storage/preview_cable.sqlite3 SWAY_CACHE_DATABASE_NAME=storage/preview_cache.sqlite3 bin/rails db:prepare db:schema:load:queue'

dip compose up --detach --force-recreate preview preview_caddy preview_cloudflared
echo "Preview is running at ${APP_BASE_URL}"
dip compose logs preview preview_caddy preview_cloudflared --follow
