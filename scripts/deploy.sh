#!/usr/bin/env zsh

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

if [[ "$1" = "google" ]]; then

    ./litestream/replicate.sh

    gcloud storage cp --recursive $(pwd)/storage/geojson gs://sway-sqlite/

    gcloud storage cp --recursive $(pwd)/storage/seeds/data gs://sway-sqlite/seeds/

    # Cloud Run requires AMD64 images
    docker buildx build . -f docker/dockerfiles/production.dockerfile --platform linux/amd64 -t us-central1-docker.pkg.dev/sway-421916/sway/sway:latest --push --compress

    gcloud run deploy sway --project=sway-421916 --region=us-central1 --image=us-central1-docker.pkg.dev/sway-421916/sway/sway:latest --revision-suffix=${1}

elif [[ "$1" = "flyio" ]]; then

    echo $GITHUB_ACCESS_TOKEN | docker login ghcr.io -u dcordz --password-stdin

    docker buildx build . -f docker/dockerfiles/production.dockerfile --platform linux/amd64 -t ghcr.io/plebeian-technology/sway:latest --compress --push

    # docker buildx build . -f docker/dockerfiles/production.dockerfile --platform linux/amd64 -t sway-prod:latest --compress

    fly deploy
fi