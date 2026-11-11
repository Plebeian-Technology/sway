#!/usr/bin/env bash
# @lat: [[local-store-uploads#Why the binary never passes through Expo]]
# Usage: upload-ios.sh [path/to/app.ipa]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
mobile="$(cd "$here/.." && pwd)"
# @lat: [[use-your-own-secret-store]]
source "$mobile/../scripts/lib/secrets.sh"

ipa="${1:-}"
if [ -z "$ipa" ]; then
    newest=""
    for candidate in "$mobile"/*.ipa; do
        [ -f "$candidate" ] || continue
        if [ -z "$newest" ] || [ "$candidate" -nt "$newest" ]; then
            newest="$candidate"
        fi
    done
    ipa="$newest"
fi
if [ -z "$ipa" ] || [ ! -s "$ipa" ]; then
    echo "upload-ios.sh: no .ipa given and none found in ${mobile##*/}/. Build one first:" >&2
    echo "  pnpm --dir mobile build:local -- --platform ios --profile production" >&2
    exit 1
fi

sway_secrets_unlock

key_id="$(sway_secrets_get SWAY_APP_STORE_CONNECT_API_KEY_ID)"
issuer_id="$(sway_secrets_get SWAY_APP_STORE_CONNECT_ISSUER_ID)"
if [ -z "$key_id" ] || [ -z "$issuer_id" ]; then
    echo "upload-ios.sh: SWAY_APP_STORE_CONNECT_API_KEY_ID or SWAY_APP_STORE_CONNECT_ISSUER_ID is empty in the secret store" >&2
    exit 1
fi

# @lat: [[local-store-uploads#Why altool dictates the key filename]]
key_dir="${API_PRIVATE_KEYS_DIR:-$HOME/.appstoreconnect/private_keys}"
if [ ! -s "$key_dir/AuthKey_$key_id.p8" ]; then
    cat >&2 <<MSG
upload-ios.sh: altool cannot find $key_dir/AuthKey_$key_id.p8

altool locates the key by name, not by path: AuthKey_<key id>.p8 in one of
./private_keys, ~/private_keys, ~/.private_keys or ~/.appstoreconnect/private_keys.
If the key is on disk under a different name, link it rather than renaming it:
  ln -s <actual file> "$key_dir/AuthKey_$key_id.p8"
MSG
    exit 1
fi

# @lat: [[local-store-uploads#Why the upload names the Apple ID rather than the bundle id]]
work="$(mktemp -d)"
log="$work/altool.log"
trap 'rm -rf "$work"' EXIT
unzip -q -o "$ipa" 'Payload/*.app/Info.plist' -d "$work" ||
    echo "upload-ios.sh: could not read Info.plist out of $ipa" >&2
plist="$(find "$work/Payload" -maxdepth 2 -name Info.plist -print -quit 2>/dev/null)"
[ -n "$plist" ] || { echo "upload-ios.sh: $ipa carries no Payload/*.app/Info.plist" >&2; exit 1; }

bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$plist")"
bundle_version="$(plutil -extract CFBundleVersion raw -o - "$plist")"
short_version="$(plutil -extract CFBundleShortVersionString raw -o - "$plist")"

apple_id="$(APP_STORE_CONNECT_API_KEY_ID="$key_id" APP_STORE_CONNECT_ISSUER_ID="$issuer_id" \
    "$here/asc.rb" app-id "$bundle_id")" ||
    { echo "upload-ios.sh: could not resolve an Apple ID for $bundle_id" >&2; exit 1; }

echo "uploading ${ipa##*/} ($bundle_id $short_version build $bundle_version)"
echo "to App Store Connect app $apple_id with key $key_id"
set +e
xcrun altool --upload-package "$ipa" --type ios \
    --apple-id "$apple_id" --bundle-id "$bundle_id" \
    --bundle-version "$bundle_version" --bundle-short-version-string "$short_version" \
    --apiKey "$key_id" --apiIssuer "$issuer_id" 2>&1 | tee "$log"
set -e

# @lat: [[local-store-uploads#Why the iOS upload reads altool's output rather than its exit code]]
if grep -qE '^[^ ]* ERROR:|"product-errors"' "$log"; then
    if grep -q "Cannot determine the Apple ID from Bundle ID" "$log"; then
        cat >&2 <<MSG

upload-ios.sh: App Store Connect has no app record this key can reach for
that bundle id. Either the record does not exist, or key $key_id has not
been granted access to it.

A record cannot be created through the API at any key role. Create it by
hand: App Store Connect -> My Apps -> + -> New App, for the bundle id above
under the team named by APPLE_TEAM_ID. Then, under Users and Access ->
Integrations, confirm this key's app access covers it.
MSG
    fi
    echo "upload-ios.sh: altool reported an error above; nothing was uploaded" >&2
    exit 1
fi
