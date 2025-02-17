#!/usr/bin/env zsh

set -eu

SKIP_FILE_UPLOADS=${1:-""}

export $(cat .env.production | xargs)

echo ""
echo "#############################################################################"
echo "deploy.sh -> RAILS_ENV=production bundle install"
echo "#############################################################################"
echo ""
RAILS_ENV=production bundle install

echo ""
echo "#############################################################################"
echo "deploy.sh -> RAILS_ENV=test install + rspec"
echo "#############################################################################"
echo ""
RAILS_ENV=test bundle install
RAILS_ENV=test bundle exec rspec

echo ""
echo "#############################################################################"
echo "deploy.sh -> Clobber rails assets so they don't get added to the docker build"
echo "#############################################################################"
echo ""
SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:clobber
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:clobber

if [[ "$SKIP_FILE_UPLOADS" != "true" && "$SKIP_FILE_UPLOADS" != "1" ]]; then
    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> Copy geojson files to google cloud gs://sway-assets/"
    echo "#############################################################################"
    echo ""
    gcloud storage cp --recursive $(pwd)/storage/geojson gs://sway-assets/

    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> Copy seed file data to google cloud gs://sway-assets/seeds/"
    echo "#############################################################################"
    echo ""
    gcloud storage cp --recursive $(pwd)/storage/seeds/data gs://sway-assets/seeds/
fi


# if [[ "$DEPLOY_ENVIRONMENT" = "google" ]]; then

#     ./litestream/replicate.sh

#     # Cloud Run requires AMD64 images
#     docker buildx build . -f docker/dockerfiles/production.dockerfile --platform linux/amd64 -t us-central1-docker.pkg.dev/sway-421916/sway/sway:latest --push --compress

#     gcloud run deploy sway --project=sway-421916 --region=us-central1 --image=us-central1-docker.pkg.dev/sway-421916/sway/sway:latest --revision-suffix=${1}

# else
    # Store an image of Sway in github
echo ""
echo "#############################################################################"
echo "deploy.sh -> Log into Github Docker Image Registry"
echo "#############################################################################"
echo ""
echo $GITHUB_ACCESS_TOKEN_FOR_DEPLOY | docker login ghcr.io -u dcordz --password-stdin

echo ""
echo "#############################################################################"
echo "deploy.sh -> Build docker image."
echo "#############################################################################"
echo ""
docker buildx build . \
    -f docker/dockerfiles/production.dockerfile \
    --platform linux/amd64 \
    -t ghcr.io/plebeian-technology/sway:latest \
    --compress \
    --push \
    --build-arg SENTRY_AUTH_TOKEN=$SENTRY_AUTH_TOKEN \
    --build-arg SENTRY_ORG=$SENTRY_ORG \
    --build-arg SENTRY_PROJECT=$SENTRY_PROJECT

echo ""
echo "#############################################################################"
echo "deploy.sh -> Deploy to fly.io"
echo "#############################################################################"
echo ""
fly deploy
# fi
