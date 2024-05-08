#!/usr/bin/env bash

export $(cat .env.github | xargs)

# echo $GITHUB_ACCESS_TOKEN | docker login ghcr.io -u dcordz --password-stdin
# deploy to github container registry

# Cloud Run requires AMD64 images
docker buildx build . -f docker/dockerfiles/production.dockerfile --platform linux/amd64 -t us-central1-docker.pkg.dev/sway-421916/sway/sway:latest --push --compress

gcloud run deploy sway --project=sway-421916 --region=us-central1 --image=us-central1-docker.pkg.dev/sway-421916/sway/sway:latest --revision-suffix=${1}
