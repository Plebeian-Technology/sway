# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.7
ARG DISTRO_NAME=trixie

FROM ruby:$RUBY_VERSION-slim-$DISTRO_NAME

# Common dependencies
# Using --mount to speed up build with caching, see https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/reference.md#run---mount
# Add the Ubuntu GIS PPA, GEOS needed for reading Shapefile provided by ConEd
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
    git-lfs \
    libvips \
    pkg-config \
    curl \
    gnupg2 \
    libssl-dev \
    python3-launchpadlib \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    less \
    libyaml-dev \
    libsqlite3-0 \
    # libnss3-tools for mkcert
    libnss3-tools
    # chromium-driver \
    # chromium \
    # ruby-selenium-webdriver \

ARG NODE_MAJOR
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=tmpfs,target=/var/log \
  curl -sL https://deb.nodesource.com/setup_$NODE_MAJOR.x | bash - && \
  DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    nodejs

# Application dependencies
# We use an external Aptfile for this, stay tuned
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=bind,source=Aptfile,target=/tmp/Aptfile \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
      $(grep -Ev '^\s*#' /tmp/Aptfile | xargs)

# Configure bundler
ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3

# Store Bundler settings in the project's root
ENV BUNDLE_APP_CONFIG=.bundle

# Uncomment this line if you want to run binstubs without prefixing with `bin/` or `bundle exec`
# ENV PATH /app/bin:$PATH

# Upgrade RubyGems and install the latest Bundler version
RUN gem update --system && \
    gem install bundler

RUN curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/arm64" && \
    chmod +x mkcert-v*-linux-arm64 && \
    cp mkcert-v*-linux-arm64 /usr/local/bin/mkcert

# Create a directory for the app code
RUN mkdir -p /app
WORKDIR /app

# Document that we're going to expose port 3333
EXPOSE 3333

ENV CAROOT=/app/tmp/cache/mkcert

# Use Bash as the default command
CMD ["/usr/bin/bash"]
