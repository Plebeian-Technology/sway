#!/usr/bin/env zsh

set -eu

SKIP_FILE_UPLOADS=${1:-""}

export $(cat .env.kamal | xargs)

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

echo ""
echo "#############################################################################"
echo "deploy.sh -> Kamal Deploy."
echo "#############################################################################"
echo ""
# dotenv -f ".env.production" kamal deploy
kamal redeploy
