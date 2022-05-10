#!/usr/bin/env bash

set -eu

LOCALE_NAME=${1}

# 0. Create sheet in google sheets

# 1. Create the locale in packages/constants/locale.json

# 2. Add the locale name and website to packages/constants/locales.ts

# 3. Create directories in storage buckets and copy shared organization assets into directory
mkdir -p packages/seeds/assets/${LOCALE_NAME}/audio
mkdir -p packages/seeds/assets/${LOCALE_NAME}/legislators
mkdir -p packages/seeds/assets/${LOCALE_NAME}/organizations
cp -r packages/seeds/assets/shared/organizations/ packages/seeds/assets/${LOCALE_NAME}/organizations/.

# 4. Add locale icon to seed/assets/<LOCALE_NAME>/<ICON_NAME>

# 5. Add geojson for locale to seeds/assets/geojson

# 6. Add new locale to users with city-region-country matching new locale name

# 7. Update legislators for users with new locale