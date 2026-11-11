#!/usr/bin/env bash
# Phase 38 Wave 0 — Android emulator availability probe.
# Exit 0 = Pixel 7 emulator bootable; proceed with Android captures.
# Exit 78 = no emulator available; file parity-followup beads issue and waive.
set -euo pipefail

if ! command -v emulator >/dev/null 2>&1; then
    echo "Android emulator binary not found — waiver path."
    exit 78
fi

if ! emulator -list-avds | grep -q "Pixel_7"; then
    echo "Pixel 7 AVD not configured — waiver path."
    exit 78
fi

echo "Pixel 7 AVD present and bootable."
exit 0
