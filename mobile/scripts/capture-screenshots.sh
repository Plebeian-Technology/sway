#!/usr/bin/env bash
# @lat: [[local-store-uploads#Why the screenshot flow navigates by deep link]]
# Usage: capture-screenshots.sh ios|android
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
mobile="$(cd "$here/.." && pwd)"

platform="${1:-}"
case "$platform" in
    ios) shots="assets/store/ios-screenshots" ;;
    android) shots="assets/store/android-screenshots" ;;
    *)
        echo "capture-screenshots.sh: usage: capture-screenshots.sh ios|android" >&2
        exit 2
        ;;
esac

command -v maestro >/dev/null || {
    echo "capture-screenshots.sh: maestro is not on the PATH. Install it with:" >&2
    echo '  curl -Ls "https://get.maestro.mobile.dev" | bash' >&2
    exit 1
}

mkdir -p "$mobile/$shots"

exec "$here/with-vault-env.sh" APPLE_BUNDLE_ID -- sh -c "
    cd '$mobile' &&
    exec maestro test .maestro/screenshots.yaml \
        -e APP_ID=\"\$APPLE_BUNDLE_ID\" \
        -e SHOTS='$shots'
"
