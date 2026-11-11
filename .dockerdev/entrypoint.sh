#!/usr/bin/env bash
# @lat: [[verification-gates#The frontend test bundle a spec run reads]]

set -u

runs_rspec=0
for arg in "$@"; do
    case "$arg" in
        rspec | */rspec) runs_rspec=1 ;;
    esac
done

if [ "$runs_rspec" = "1" ]; then
    # @lat: [[verification-gates#The frontend test bundle a spec run reads]]
    if [ -z "${SWAY_VITE_BUILD_DIR:-}" ]; then
        SWAY_VITE_BUILD_DIR="vite-test/run-adhoc-${HOSTNAME:-$$}"
        export SWAY_VITE_BUILD_DIR
    fi
    /app/scripts/dip/vite-test-build.sh ensure || exit $?
fi

if [ "$#" -eq 0 ]; then
    exec /bin/bash
fi

exec "$@"
