ARG RUBY_VERSION=3.4.5
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim AS base

LABEL fly_launch_runtime="rails"

# Rails app lives here
WORKDIR /rails

# Set production environment
ARG SENTRY_ORG="sway-a6" \
    SENTRY_PROJECT="sway"

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        build-essential \
        libyaml-dev \
        libsqlite3-0 \
        nodejs \
        npm \
        pkg-config && \
    apt-get clean

# Install application gems
COPY Gemfile Gemfile.lock package.json package-lock.json ./

RUN --mount=type=secret,id=SENTRY_AUTH_TOKEN \
    SENTRY_AUTH_TOKEN=$(cat /run/secrets/SENTRY_AUTH_TOKEN) \
    bundle config set build.sqlite3 "--with-sqlite-cflags='-DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_PAGE_SIZE=16384 -DSQLITE_DQS=0 -DSQLITE_ENABLE_FTS5 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_MAX_EXPR_DEPTH=0 -DSQLITE_OMIT_PROGRESS_CALLBACK -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_USE_ALLOCA'" && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile && \
    npm install

# Copy application code
COPY . .
COPY vite.config.build.ts vite.config.ts

# Precompile bootsnap code for faster boot times
# and...
# You can also set ENV["SECRET_KEY_BASE_DUMMY"] to trigger the use of a randomly generated
# secret_key_base that's stored in a temporary file. This is useful when precompiling assets for
# production as part of a build step that otherwise does not need access to the production secrets.
RUN --mount=type=secret,id=SENTRY_AUTH_TOKEN \
    SENTRY_AUTH_TOKEN=$(cat /run/secrets/SENTRY_AUTH_TOKEN) \
    bundle exec bootsnap precompile app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf app/frontend && \
    rm -rf app/stylesheets


# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp config

USER rails:rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3333

CMD ["./bin/rails", "server", "-u", "puma", "-b", "0.0.0.0", "-p", "3333", "-e", "production"]
