# syntax=docker/dockerfile:1

ARG RUBY_VERSION=4.0.9
ARG DISTRO_NAME=trixie

FROM ruby:$RUBY_VERSION-slim-$DISTRO_NAME

# Common dependencies
# Using --mount to speed up build with caching, see https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/reference.md#run---mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=tmpfs,target=/var/log \
  rm -f /etc/apt/apt.conf.d/docker-clean; \
  echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
  apt-get update -qq && \
  DEBIAN_FRONTEND=noninteractive apt-get -yq dist-upgrade && \
  DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    build-essential \
    git \
    pkg-config \
    curl \
    gnupg2 \
    libssl-dev \
    ca-certificates \
    less \
    libyaml-dev \
    libsqlite3-0 \
    sqlite3 \
    # libnss3-tools for mkcert
    libnss3-tools \
    chromium-driver \
    chromium \
    # @lat: [[development-container-settings#What the container declares about the pipeline's tools]]
    golang-go \
    mupdf-tools \
    tesseract-ocr \
    tesseract-ocr-eng && \
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*

# @lat: [[development-container-settings#Why the development image proves the browser can start]]
RUN chromium --headless=new --no-sandbox --disable-gpu \
    --disable-dev-shm-usage --dump-dom about:blank > /dev/null

ARG NODE_MAJOR=24
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=tmpfs,target=/var/log \
  curl -sL https://deb.nodesource.com/setup_$NODE_MAJOR.x | bash - && \
  DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    nodejs && \
  npm i -g pnpm@12 && \
  strip --strip-unneeded /usr/bin/node && \
  rm -rf /usr/include/node /usr/share/doc/nodejs /root/.npm /tmp/*

# Configure bundler
# Store Bundler settings in the project's root
ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  BUNDLE_APP_CONFIG=.bundle \
  IS_DOCKER=1

# @lat: [[production-image#Why the SQLite options are written as local bundler configuration]]
ENV BUNDLE_BUILD__SQLITE3="--with-sqlite-cflags='-DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DQS=0 -DSQLITE_ENABLE_FTS5 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_MAX_EXPR_DEPTH=0 -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_USE_ALLOCA'"

# @lat: [[development-container-settings#Why the development image excludes its build context and installs Bundler outside the gem volume]]
RUN gem install --install-dir /usr/local/lib/ruby/gems/4.0.0 --bindir /usr/local/bin bundler -N && \
    rm -rf /root/.gem /usr/local/bundle/cache /usr/local/lib/ruby/gems/4.0.0/cache/* && \
    curl -fsSL "https://dl.filippo.io/mkcert/latest?for=linux/$(dpkg --print-architecture)" -o /usr/local/bin/mkcert && \
    chmod +x /usr/local/bin/mkcert

WORKDIR /app

# Document that we're going to expose port 3000
EXPOSE 3000

ENV CAROOT=/app/tmp/cache/mkcert

# Debian trixie ships tesseract 5.x; tessdata lives under
# /usr/share/tesseract-ocr/5/tessdata. MupdfExtractor raises early if this
# env var is unset (see app/services/mupdf_extractor.rb). compose.yml mirrors
# this default into the dev container env so callers don't have to set it.
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata
# @lat: [[development-container-settings#What the container declares about the pipeline's tools#Why OCR is capped to a single OpenMP thread]]
ENV OMP_THREAD_LIMIT=1

# Use Bash as the default command
CMD ["/usr/bin/bash"]
