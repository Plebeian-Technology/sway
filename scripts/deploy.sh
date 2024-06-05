#!/usr/bin/env bash

export $(cat .env.github | xargs)

# Build a local image
# docker buildx build . -f docker/dockerfiles/production.dockerfile -t sway:latest --compress

# cp vite.config.ts tmp/vite.config.ts && \
# cp vite.config.build.ts vite.config.ts && \
# RAILS_ENV=production bundle exec bootsnap precompile app/ lib/ && \
# cp tmp/vite.config.ts vite.config.ts
# RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
# gcloud storage cp --recursive $(pwd)/public/* gs://sway-public

# Clobber assets so they don't get added to the docker build
SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:clobber
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:clobber

gcloud storage cp --recursive $(pwd)/storage/geojson gs://sway-sqlite/

gcloud storage cp --recursive $(pwd)/storage/seeds/data gs://sway-sqlite/seeds/


# Cloud Run requires AMD64 images
docker buildx build . -f docker/dockerfiles/production.dockerfile --platform linux/amd64 -t us-central1-docker.pkg.dev/sway-421916/sway/sway:latest --push --compress

gcloud run deploy sway --project=sway-421916 --region=us-central1 --image=us-central1-docker.pkg.dev/sway-421916/sway/sway:latest --revision-suffix=${1}
