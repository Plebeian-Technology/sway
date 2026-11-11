#!/usr/bin/env bash
# Phase 38 — verify every in-scope screen has paired web/mobile/diff PNGs.
# Exit 0 = pass; non-zero = at least one PNG missing.
#
# In-scope screens come from 38-UI-SPEC.md §"In-Scope Screen List" (18 entries;
# PARITY-07 = closed-vacuous per Phase 34 D-01 — no separate capture).
# Mobile-only screens (no web counterpart) only require the mobile PNG.

set -euo pipefail

DIR="$(cd "$(dirname "$0")/../docs/parity-evidence" && pwd)"

SCREENS=(
    bill-of-the-week
    bills
    bill-detail
    legislators
    legislator-detail
    orgs
    org-detail
    auth-phone-entry
    auth-code-revealed
    auth-loading
    auth-preview-cta
    device-unsupported
    address-onboarding
    address-edit
    profile
    notifications
    theme
    passkey
)

# Mobile-only screens skip the web/diff requirement (per UI-SPEC [no-web-counterpart]).
MOBILE_ONLY=(device-unsupported address-edit profile)

fail=0
total="${#SCREENS[@]}"

for s in "${SCREENS[@]}"; do
    is_mobile_only=0
    for m in "${MOBILE_ONLY[@]}"; do
        [[ "$m" == "$s" ]] && is_mobile_only=1
    done
    if [[ "$is_mobile_only" -eq 1 ]]; then
        if [[ ! -f "$DIR/mobile/$s.png" ]]; then
            echo "MISSING mobile/$s.png"
            fail=1
        fi
    else
        for sub in web mobile diff; do
            if [[ ! -f "$DIR/$sub/$s.png" ]]; then
                echo "MISSING $sub/$s.png"
                fail=1
            fi
        done
    fi
done

if [[ "$fail" -eq 0 ]]; then
    echo "evidence pack: ${total}/${total} screens have all required PNGs"
fi
exit "$fail"
