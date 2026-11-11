# syntax=docker/dockerfile:1

ARG RUBY_VERSION=4.0.9

# ─── base ───────────────────────────────────────────────────────────
# Shared by build stages and the final runtime image.
FROM registry.docker.com/library/ruby:${RUBY_VERSION}-alpine AS base

WORKDIR /rails

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_JOBS="4" \
    BUNDLE_RETRY="3" \
    PNPM_CACHE_FOLDER="/usr/local/share/.cache/pnpm"

# @lat: [[production-image#Where the compiled Ruby cache lives]]
# /bootsnap is still the right thing to COPY.
ENV BOOTSNAP_CACHE_DIR="/bootsnap"

# ─── build-deps ─────────────────────────────────────────────────────
# System packages + bundler + node/npm. Cached until apk list or base bumps;
# unaffected by Gemfile / package.json churn.
FROM base AS build-deps

ENV BUNDLE_FORCE_COLOR="true" \
    FORCE_COLOR="1"

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    apk --cache-dir=/var/cache/apk -U add \
        build-base \
        ca-certificates \
        git \
        linux-headers \
        nodejs \
        npm \
        openssl-dev \
        pkgconf \
        tzdata \
        yaml-dev \
        zlib-dev

# @lat: [[production-image#Why the package manager floats within its major]]
RUN gem install bundler -N && \
    npm install -g pnpm@12 && \
    rm -rf /root/.npm /root/.gem "${BUNDLE_PATH}/cache"

# ─── gems (parallel) ────────────────────────────────────────────────
# bundle install. Invalidated by Gemfile / Gemfile.lock only — runs in
# parallel with the nodemods stage under BuildKit.
FROM build-deps AS gems

COPY Gemfile Gemfile.lock ./

# @lat: [[production-image#Why the SQLite options are written as local bundler configuration]]
RUN bundle config set --local build.sqlite3 \
    "--with-sqlite-cflags='-DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DQS=0 -DSQLITE_ENABLE_FTS5 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_MAX_EXPR_DEPTH=0 -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_USE_ALLOCA'"

# @lat: [[production-image#Where the compiled Ruby cache lives]]
RUN --mount=type=cache,target=/root/.bundle/cache,sharing=locked \
    --mount=type=cache,target=/usr/local/bundle/ruby/4.0.0/cache,sharing=locked \
    rm -rf /root/.bundle/cache/extensions && \
    bundle install && \
    bundle clean --force && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git \
           "${BUNDLE_PATH}"/ruby/*/gems/nokogiri-*/lib/nokogiri/3.* \
           "${BUNDLE_PATH}"/ruby/*/gems/*/rbi \
           "${BUNDLE_PATH}"/ruby/*/gems/*/sig \
           "${BUNDLE_PATH}"/ruby/*/gems/*/spec \
           "${BUNDLE_PATH}"/ruby/*/gems/*/test \
           "${BUNDLE_PATH}"/ruby/*/gems/*/tests \
           "${BUNDLE_PATH}"/ruby/*/gems/*/doc \
           "${BUNDLE_PATH}"/ruby/*/gems/*/docs \
           "${BUNDLE_PATH}"/ruby/*/gems/*/examples \
           "${BUNDLE_PATH}"/ruby/*/gems/*/benchmarks \
           "${BUNDLE_PATH}"/ruby/*/gems/rbs-*/core \
           "${BUNDLE_PATH}"/ruby/*/gems/rbs-*/stdlib \
           "${BUNDLE_PATH}"/ruby/*/gems/rbs-*/src \
           "${BUNDLE_PATH}"/ruby/*/gems/rbs-*/include \
           "${BUNDLE_PATH}"/ruby/*/gems/prism-*/src \
           "${BUNDLE_PATH}"/ruby/*/gems/prism-*/include && \
    find "${BUNDLE_PATH}"/ruby/*/gems/ -type d \( -name ports -o -name tmp \) -prune -exec rm -rf {} + && \
    find "${BUNDLE_PATH}"/ruby/*/gems/ -type f \( -name '*.o' -o -name '*.a' -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' -o -name 'Makefile' -o -name 'mkmf.log' -o -name 'gem_make.out' \) -delete && \
    find /usr/local/bundle -name '*.so' -exec strip --strip-unneeded {} + && \
    bundle exec bootsnap precompile --gemfile

# ─── nodemods (parallel) ────────────────────────────────────────────
# pnpm install. Invalidated by package.json / pnpm-lock.yaml only.
# @lat: [[production-image#Why the package manager floats within its major]]
FROM build-deps AS nodemods

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN --mount=type=cache,target=/usr/local/share/.cache/pnpm,sharing=locked \
    pnpm install --frozen-lockfile --prefer-offline && \
    find node_modules -type d -name .cache -prune -exec rm -rf {} +

# ─── build ──────────────────────────────────────────────────────────
# Source COPY + bootsnap app precompile + Vite assets:precompile.
# Inherits gems; bind-mounts node_modules from nodemods during the asset build.
FROM gems AS build

# @lat: [[deploy-values-boot-check#Keeping one installation's values out of the tracked repository]]
ARG VITE_SWAY_ASSETS_BUCKET=""
ENV VITE_SWAY_ASSETS_BUCKET=${VITE_SWAY_ASSETS_BUCKET}

# Which copy of Sway this is: the cloud account, the two buckets, the
# Litestream replica path, and the names this machine answers to. None of them
# are credentials — see deploy/config/sway.env.example.
#
# WHY A BUILD NEEDS THEM AT ALL, which is not obvious. The line below runs
# `assets:precompile`, and sprockets-rails makes that task depend on
# `environment` — so building the assets starts the whole application in
# production mode. config/environments/production.rb, every initializer and
# every eagerly loaded class run right here, and six values are asked for
# before a single asset is written:
#
#   config/environments/production.rb      RAILS_ALLOWED_HOSTS
#   lib/sway_google_cloud_storage.rb       SWAY_GCP_PROJECT_ID
#                                          SWAY_GCS_BUCKET_ASSETS
#   app/services/database_backup_service.rb  SWAY_GCS_BUCKET_DB
#   app/services/litestream/replica_position.rb  SWAY_LITESTREAM_PATH
#   config/initializers/deploy_values.rb   SWAY_GCS_BUCKET_LEGISLATION,
#                                          plus all four of the above
#
# The file those normally come from, deploy/config/sway.env, is kept out of the
# build on purpose: the sibling ignore file drops every *.env*, because that
# file names one person's account and this repo is public. So they arrive here
# as build settings from config/deploy.yml `builder.args` instead.
#
# THESE DO NOT REACH THE RUNNING CONTAINER, and that is deliberate. This is the
# build stage; the final stage below never sees them. The container gets its own
# copies from `env: clear:` in config/deploy.yml, so changing a bucket later
# costs a redeploy rather than a rebuild.
#
# Empty defaults keep a bare `docker build` working up to the first value
# somebody actually asks for, which then stops and names itself rather than
# guessing. A guessed bucket name is the worst outcome available here: every
# upload succeeds, into a bucket nobody reads, and the loss shows up during a
# restore.
ARG RAILS_ALLOWED_HOSTS="" \
    SWAY_GCP_PROJECT_ID="" \
    SWAY_GCS_BUCKET_ASSETS="" \
    SWAY_GCS_BUCKET_DB="" \
    SWAY_GCS_BUCKET_LEGISLATION="" \
    SWAY_LITESTREAM_PATH=""
ENV RAILS_ALLOWED_HOSTS=${RAILS_ALLOWED_HOSTS} \
    SWAY_GCP_PROJECT_ID=${SWAY_GCP_PROJECT_ID} \
    SWAY_GCS_BUCKET_ASSETS=${SWAY_GCS_BUCKET_ASSETS} \
    SWAY_GCS_BUCKET_DB=${SWAY_GCS_BUCKET_DB} \
    SWAY_GCS_BUCKET_LEGISLATION=${SWAY_GCS_BUCKET_LEGISLATION} \
    SWAY_LITESTREAM_PATH=${SWAY_LITESTREAM_PATH}

COPY . .

# Which commit this build came from. vite.config.ts sends it to Sentry as the
# name for this build's source maps, so the Source Maps page names a real
# commit instead of the word "undefined" — see vite/sentryReleaseName.ts.
#
# THE SAME VALUE IS DECLARED AGAIN AT THE END OF THE FINAL STAGE, and both are
# needed. That one is read at runtime by Sway::Release; this one is read while
# the frontend is built, and a build stage cannot see the final stage's values.
#
# It costs no build time. A new commit changes the `COPY . .` above, which
# already rebuilds everything below it, so this line only ever changes when
# that layer was going to be rebuilt anyway.
#
# ENV as well as ARG, matching VITE_SWAY_ASSETS_BUCKET above. Docker does hand
# a build setting to the command below on its own, but vite reads this several
# processes deep, and ENV is the form that is certain to travel that far. This
# stage is thrown away, so the value never reaches the running container from
# here.
ARG SWAY_RELEASE_SHA=""
ENV SWAY_RELEASE_SHA=${SWAY_RELEASE_SHA}

RUN --mount=type=bind,from=nodemods,source=/rails/node_modules,target=/rails/node_modules,rw \
    --mount=type=secret,id=SENTRY_AUTH_TOKEN \
    --mount=type=secret,id=VITE_GOOGLE_MAPS_API_KEY \
    --mount=type=secret,id=RAILS_MASTER_KEY \
    --mount=type=secret,id=VITE_SENTRY_DSN \
    --mount=type=secret,id=SENTRY_ORG \
    --mount=type=secret,id=SENTRY_PROJECT \
    # @lat: [[production-image#Why a build secret has to be exported]]
    export SENTRY_AUTH_TOKEN="$(cat /run/secrets/SENTRY_AUTH_TOKEN 2>/dev/null || true)" && \
    export VITE_GOOGLE_MAPS_API_KEY="$(cat /run/secrets/VITE_GOOGLE_MAPS_API_KEY)" && \
    export RAILS_MASTER_KEY="$(cat /run/secrets/RAILS_MASTER_KEY)" && \
    # @lat: [[browser-error-reporting#The cache trap when toggling a build secret]]
    export VITE_SENTRY_DSN="$(cat /run/secrets/VITE_SENTRY_DSN 2>/dev/null || true)" && \
    export SENTRY_ORG="$(cat /run/secrets/SENTRY_ORG 2>/dev/null || true)" && \
    export SENTRY_PROJECT="$(cat /run/secrets/SENTRY_PROJECT 2>/dev/null || true)" && \
    bundle exec bootsnap precompile app/ lib/ config/ && \
    # SKIP_VITE_INSTALL=1: rails_vite hooks vite:build onto assets:precompile,
    # and vite:build otherwise runs `pnpm install` first. The nodemods stage
    # already installed from the frozen lockfile and this step bind-mounts that
    # node_modules in, so a second install would only risk changing it.
    SECRET_KEY_BASE_DUMMY=1 SKIP_VITE_INSTALL=1 ./bin/rails assets:precompile && \
    # SWAY: snapshot frontend OSS licenses while node_modules is here
    # (consumed by OpenSourceLicensesService for the public /licenses page).
    # @lat: [[oss-license-snapshot#Why a failure is now audible twice]]
    (bundle exec rake sway:licenses:frontend || \
        echo "[build] ###### OSS LICENCE SNAPSHOT FAILED — /licenses ships one row saying so ######" >&2) && \
    # @lat: [[production-image#Why the source maps are deleted only when they were uploaded]]
    if [ -n "${SENTRY_AUTH_TOKEN}" ] && [ -n "${SENTRY_ORG}" ] && [ -n "${SENTRY_PROJECT}" ]; then \
        echo "[build] removing source maps ($(find public -name '*.map' | wc -l) files); Sentry has them" && \
        find public -name '*.map' -delete; \
    else \
        echo "[build] keeping source maps — no Sentry upload was configured, so nothing else holds a copy"; \
    fi && \
    # @lat: [[production-image#What the final image keeps of the frontend]]
    find app/frontend -mindepth 1 -maxdepth 1 ! -name sway_constants -exec rm -rf {} + && \
    find app/frontend/sway_constants -mindepth 1 ! -name errorScrubRules.json -exec rm -rf {} + && \
    rm -rf tmp/cache

# ─── final ──────────────────────────────────────────────────────────
FROM base

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    apk --cache-dir=/var/cache/apk -U add \
        bash \
        ca-certificates \
        # @lat: [[production-image#Why the allocator is replaced, and how that can be undone silently]]
        jemalloc \
        libstdc++ \
        tzdata && \
    addgroup -S rails && \
    adduser -S -G rails -h /home/rails rails

# @lat: [[development-container-settings#What the container declares about the pipeline's tools#Why OCR is capped to a single OpenMP thread]]
ENV OMP_THREAD_LIMIT=1

# @lat: [[production-image#Why the allocator is replaced, and how that can be undone silently]]
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2 \
    MALLOC_CONF="dirty_decay_ms:1000,muzzy_decay_ms:1000,narenas:2,background_thread:true"

COPY --from=build /usr/local/bundle /usr/local/bundle

# @lat: [[production-image#Where the compiled Ruby cache lives]]
COPY --from=build --chown=rails:rails /bootsnap /bootsnap

# Piece-wise COPY so unchanged dirs become reusable layers at push time.
COPY --from=build /rails/app    /rails/app
COPY --from=build /rails/bin    /rails/bin
COPY --from=build /rails/lib    /rails/lib
COPY --from=build /rails/Gemfile /rails/Gemfile.lock /rails/Rakefile /rails/config.ru ./

# @lat: [[production-image#Ownership is set by the copy, never by a later chown]]
COPY --from=build --chown=rails:rails /rails/config /rails/config
COPY --from=build --chown=rails:rails /rails/db     /rails/db
COPY --from=build --chown=rails:rails /rails/public /rails/public

# Created empty here rather than copied, so chowning them costs nothing. storage
# is a mount point in production (config/deploy.yml `volumes:`) and the host
# directory's ownership wins at run time; it is created so the container still
# starts when nothing is mounted.
#
# keys/ is where SwayGoogleCloudStorage writes the service-account key at boot;
# 0700 because that file is a private key.
# @lat: [[explanation/keyfile-write-directory#Why write_keyfile controls its own disk writes#Creating the directory needs a writable parent]]
RUN mkdir -p log tmp/pids tmp/sockets storage keys && \
    chown rails:rails log tmp tmp/pids tmp/sockets storage keys && \
    chmod 700 keys

# SWAY release metadata — values computed by scripts/deploy.sh and passed via
# config/deploy.yml `builder.args`. Declared here, at the very end of the final
# stage, so a new release (changed args) invalidates only this trivial ENV
# layer — never the gem/bundle/asset layers above. Read at runtime by
# Sway::Release and surfaced in the UI (logo tooltip + /version page).
ARG SWAY_RELEASE_VERSION="" \
    SWAY_RELEASE_SHA="" \
    SWAY_PREVIOUS_SHA="" \
    SWAY_DEPLOYED_AT="" \
    SWAY_UNCOMMITTED_DIGEST=""
ENV SWAY_RELEASE_VERSION=${SWAY_RELEASE_VERSION} \
    SWAY_RELEASE_SHA=${SWAY_RELEASE_SHA} \
    SWAY_PREVIOUS_SHA=${SWAY_PREVIOUS_SHA} \
    SWAY_DEPLOYED_AT=${SWAY_DEPLOYED_AT} \
    SWAY_UNCOMMITTED_DIGEST=${SWAY_UNCOMMITTED_DIGEST}

USER rails:rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3333

CMD ["./bin/rails", "server", "-u", "puma", "-b", "0.0.0.0", "-p", "3333", "-e", "production"]
