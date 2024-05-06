#!/usr/bin/env bash

export RAILS_ENV="production"
export BUNDLE_DEPLOYMENT="1"
export BUNDLE_PATH="/usr/local/bundle"
export BUNDLE_WITHOUT="development:test"

cd /home/rails

chown -R rails:rails db log storage tmp config

apt-get update
apt-get install --no-install-recommends -y \
        build-essential \
        libsqlite3-0 \
        libvips \
        pkg-config \
        nodejs \
        npm
apt-get clean
rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
bundle install && \
rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

npm install

# Use build vite config
mv vite.config.build.ts vite.config.ts

# Precompile bootsnap code for faster boot times
bundle exec bootsnap precompile app/ lib/

# You can also set ENV["SECRET_KEY_BASE_DUMMY"] to trigger the use of a randomly generated
# secret_key_base that's stored in a temporary file. This is useful when precompiling assets for
# production as part of a build step that otherwise does not need access to the production secrets.
SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

./bin/rails db:prepare