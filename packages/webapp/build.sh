#!/usr/bin/env bash

set -eu

APP=${1}

if [[ "$APP" != "app-sway" && "$APP" != "app-widgets" ]]; then
    echo "First argument to start.sh must be an app name, either 'app-sway' or 'app-widgets'"
else
    echo "export * from \"./${APP}\";" > src/index.ts

    npx -C . react-scripts build

    if [[ "$APP" = "app-sway" ]]; then
        echo "Copying service-worker.js to public directory"
        cp build/service-worker.js public/service-worker.js

        echo "Copying service-worker.js.map to public directory"
        cp build/service-worker.js.map public/service-worker.js.map
    fi
fi
