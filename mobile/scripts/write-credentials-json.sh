#!/usr/bin/env bash
# @lat: [[local-store-uploads#Why credentials.json is generated, never committed]]
# @lat: [[local-store-uploads#Why one platform's material is enough]]
# Usage: write-credentials-json.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
mobile="$(cd "$here/.." && pwd)"
# @lat: [[use-your-own-secret-store]]
source "$mobile/../scripts/lib/secrets.sh"

dist_cert="credentials/ios/dist-cert.p12"
profile="credentials/ios/profile.mobileprovision"
keystore="credentials/android/keystore.jks"

have_ios=false
[ -s "$mobile/$dist_cert" ] && [ -s "$mobile/$profile" ] && have_ios=true
have_android=false
[ -s "$mobile/$keystore" ] && have_android=true

if ! $have_ios && ! $have_android; then
    cat >&2 <<MSG
write-credentials-json.sh: no signing material found under credentials/

Android wants $keystore, and its keystore must be the one Play
already knows: a fresh one is rejected once an app is bound to a signing key,
so 'eas credentials' is the way to recover what Expo holds.

iOS wants $dist_cert and
$profile. Those are replaceable, so Apple's
Developer portal is the straightforward source when Expo cannot be reached.
MSG
    exit 1
fi

# @lat: [[local-store-uploads#Why the script tightens modes it did not set]]
chmod go-rwx "$mobile/credentials" 2>/dev/null || true
for f in "$mobile/$dist_cert" "$mobile/$profile" "$mobile/$keystore"; do
    [ -e "$f" ] || continue
    chmod go-rwx "$(dirname "$f")" "$f" 2>/dev/null || true
done

sway_secrets_unlock

get() {
    local value
    if ! value="$(sway_secrets_get "$1")" || [ -z "$value" ]; then
        echo "write-credentials-json.sh: $1 is missing or empty in the secret store" >&2
        exit 1
    fi
    printf '%s' "$value"
}

export HAVE_IOS="$have_ios" HAVE_ANDROID="$have_android"
export DIST_CERT_PATH="$dist_cert" PROFILE_PATH="$profile" KEYSTORE_PATH="$keystore"
if $have_ios; then
    export CERT_PASSWORD="$(get SWAY_IOS_DIST_CERT_PASSWORD)"
fi
if $have_android; then
    export KEYSTORE_PASSWORD="$(get SWAY_ANDROID_KEYSTORE_PASSWORD)"
    export KEY_ALIAS="$(get SWAY_ANDROID_KEY_ALIAS)"
    export KEY_PASSWORD="$(get SWAY_ANDROID_KEY_PASSWORD)"
fi

out="$mobile/credentials.json"
umask 077
ruby -rjson -e '
    credentials = {}
    if ENV["HAVE_ANDROID"] == "true"
      credentials["android"] = {
        "keystore" => {
          "keystorePath" => ENV.fetch("KEYSTORE_PATH"),
          "keystorePassword" => ENV.fetch("KEYSTORE_PASSWORD"),
          "keyAlias" => ENV.fetch("KEY_ALIAS"),
          "keyPassword" => ENV.fetch("KEY_PASSWORD")
        }
      }
    end
    if ENV["HAVE_IOS"] == "true"
      credentials["ios"] = {
        "provisioningProfilePath" => ENV.fetch("PROFILE_PATH"),
        "distributionCertificate" => {
          "path" => ENV.fetch("DIST_CERT_PATH"),
          "password" => ENV.fetch("CERT_PASSWORD")
        }
      }
    end
    print JSON.pretty_generate(credentials)
' > "$out"

platforms=()
$have_android && platforms+=(android)
$have_ios && platforms+=(ios)
echo "wrote ${out#"$mobile"/} for ${platforms[*]} (mode $(stat -f '%Lp' "$out"), gitignored)"
if ! $have_ios; then
    echo "ios is absent, so 'eas build --platform ios' will fail until $dist_cert and $profile exist" >&2
fi
if ! $have_android; then
    echo "android is absent, so 'eas build --platform android' will fail until $keystore exists" >&2
fi
