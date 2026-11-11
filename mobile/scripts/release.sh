#!/usr/bin/env bash
# @lat: [[local-store-uploads#Why one script runs the whole release]]
# Usage: release.sh ios|android [--skip-build]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
mobile="$(cd "$here/.." && pwd)"

platform="${1:-}"
case "$platform" in
    ios | android) ;;
    *)
        echo "release.sh: usage: release.sh ios|android [--skip-build]" >&2
        exit 2
        ;;
esac
skip_build=false
[ "${2:-}" = "--skip-build" ] && skip_build=true

step() { printf '\n==> %s\n' "$1"; }
fail() {
    echo "release.sh: $1" >&2
    exit 1
}

step "Checking the working tree"
if [ -n "$(git -C "$mobile" status --porcelain 2>/dev/null)" ]; then
    echo "working tree is dirty; the build fingerprint will not name a commit"
fi

step "Writing credentials.json from the vault"
"$here/write-credentials-json.sh"

# @lat: [[local-store-uploads#Why the release reads its own API address from app.json]]
api_base_url="${EXPO_PUBLIC_API_URL:-$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("expo", "extra", "apiBaseUrl").to_s' "$mobile/app.json")}"
[ -n "$api_base_url" ] || fail "no apiBaseUrl in app.json and EXPO_PUBLIC_API_URL is unset"

step "Preflight for $platform"
if [ "$platform" = "ios" ]; then
    for f in credentials/ios/dist-cert.p12 credentials/ios/profile.mobileprovision; do
        [ -s "$mobile/$f" ] || fail "missing $f"
    done
    profile_cert="$(security cms -D -i "$mobile/credentials/ios/profile.mobileprovision" 2>/dev/null |
        plutil -extract DeveloperCertificates.0 raw -o - - 2>/dev/null |
        base64 -d 2>/dev/null | openssl x509 -inform DER -noout -fingerprint -sha1 2>/dev/null |
        sed 's/.*=//; s/://g')"
    [ -n "$profile_cert" ] || fail "could not read the certificate out of profile.mobileprovision"
    echo "profile embeds certificate $profile_cert"
else
    [ -s "$mobile/credentials/android/keystore.jks" ] || fail "missing credentials/android/keystore.jks"
    [ -s "$mobile/credentials/play-service-account.json" ] ||
        fail "missing credentials/play-service-account.json"
fi

if $skip_build; then
    step "Skipping the build as asked"
else
    step "Building $platform against $api_base_url"
    EXPO_PUBLIC_API_URL="$api_base_url" "$here/with-vault-env.sh" \
        APPLE_BUNDLE_ID APPLE_TEAM_ID EAS_PROJECT_ID EXPO_OWNER \
        SENTRY_DSN_MOBILE SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT \
        -- eas build --local --profile production --platform "$platform"
fi

step "Uploading $platform"
if [ "$platform" = "ios" ]; then
    "$here/upload-ios.sh"
else
    "$here/with-vault-env.sh" APPLE_BUNDLE_ID -- "$here/upload-android.rb"
fi

step "Done"
if [ "$platform" = "ios" ]; then
    echo "the build appears under TestFlight once App Store Connect finishes processing"
else
    echo "the build is on Play's internal track"
fi
