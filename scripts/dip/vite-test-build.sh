#!/usr/bin/env bash
# @lat: [[verification-gates#The frontend test bundle a spec run reads]]

set -u

VITE_INPUT_FILES="package.json pnpm-lock.yaml vite.config.ts tsconfig.json tsconfig.node.json config/vite.json"
VITE_INPUT_TREE="app/frontend"
STAMP_NAME=".frontend-inputs"

hash_command() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum
    else
        shasum -a 256
    fi
}

file_digests() {
    if command -v sha256sum >/dev/null 2>&1; then
        xargs -0 -r sha256sum
    else
        xargs -0 -r shasum -a 256
    fi
}

build_dir() {
    printf 'public/%s\n' "${SWAY_VITE_BUILD_DIR:-vite-test}"
}

input_hash() {
    root="${1:-.}"
    (
        cd -- "$root" || exit 1
        if [ -d "$VITE_INPUT_TREE" ]; then
            find "$VITE_INPUT_TREE" -type f -print0 | LC_ALL=C sort -z | file_digests
        fi
        for file in $VITE_INPUT_FILES; do
            if [ -f "$file" ]; then
                printf '%s\n' "$file"
                cat "$file"
            fi
        done
    ) | hash_command | cut -d' ' -f1
}

stamped_hash() {
    stamp="$(build_dir)/$STAMP_NAME"
    [ -f "$stamp" ] && cat "$stamp"
}

build() {
    pnpm vite build --mode test || return $?
    mkdir -p "$(build_dir)"
    input_hash . >"$(build_dir)/$STAMP_NAME"
}

case "${1:-ensure}" in
    hash)
        input_hash "${2:-.}"
        ;;
    build)
        build
        ;;
    ensure)
        wanted="$(input_hash .)"
        if [ "$wanted" = "$(stamped_hash || true)" ]; then
            exit 0
        fi
        echo "vite-test-build: the frontend changed since $(build_dir) was built — rebuilding." >&2
        build
        ;;
    *)
        echo "vite-test-build.sh: hash [root] | build | ensure" >&2
        exit 64
        ;;
esac
