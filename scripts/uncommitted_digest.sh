#!/usr/bin/env bash
# Print a short fingerprint of everything in the working tree that was never
# committed, or print nothing at all when the tree is clean.
#
# @lat: [[testing-the-toolchain#A script is proved by running it]]
set -euo pipefail

if [[ -z "$(git status --porcelain)" ]]; then
    exit 0
fi

# @lat: [[system-shape#Deployment#The release fingerprint never runs a diff converter]]
{ git diff HEAD --no-textconv; git status --porcelain; } | shasum -a 256 | cut -c1-8
