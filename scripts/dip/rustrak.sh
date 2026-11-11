#!/usr/bin/env bash
# @lat: [[error-reporting-in-tests#Where a browser's error reports go during a spec run]]

# Rustrak panics on an empty cookie key ("TooShort(0)"). Its random default
# applies only when the variable is ABSENT, and compose passes "". 2026-08-10.
sway_rustrak_session_key() {
    if [ -z "${RUSTRAK_SESSION_SECRET_KEY:-}" ]; then
        if [ ! -f config/rustrak_session.key ]; then
            openssl rand -hex 32 >config/rustrak_session.key
            chmod 600 config/rustrak_session.key
            echo "rustrak: created config/rustrak_session.key for the local error collector." >&2
        fi
        RUSTRAK_SESSION_SECRET_KEY="$(cat config/rustrak_session.key)"
    fi
    export RUSTRAK_SESSION_SECRET_KEY
}

# The collector reads CREATE_SUPERUSER only while it has no users, and sign-up is
# always refused. Start once without one and the dashboard is locked for good.
sway_rustrak_superuser() {
    if [ -z "${RUSTRAK_SUPERUSER:-}" ]; then
        if [ ! -f config/rustrak_admin.key ]; then
            printf 'dev@sway.local:%s\n' "$(openssl rand -hex 12)" >config/rustrak_admin.key
            chmod 600 config/rustrak_admin.key
            echo "rustrak: created config/rustrak_admin.key — the error dashboard login." >&2
        fi
        RUSTRAK_SUPERUSER="$(cat config/rustrak_admin.key)"
    fi
    export RUSTRAK_SUPERUSER
}

# Never fatal: a collector that will not start must not stop the app, or a test
# run, from starting.
sway_rustrak_start() {
    dip compose up -d rustrak >/dev/null 2>&1 || true
    bin/rustrak-provision ||
        echo "rustrak: the collector has no project, so errors are not recorded." >&2
    bin/rustrak-mcp-token >/dev/null 2>&1 || true
}

# One project, two routes. Which one a caller needs depends on where the
# reporting thing RUNS: on the host, or inside Docker.
#
# Empty when there is no project, which correctly turns reporting off.
sway_rustrak_host_dsn() {
    [ -f config/rustrak_project.key ] || return 0
    cat config/rustrak_project.key
}

sway_rustrak_container_dsn() {
    [ -f config/rustrak_project.key ] || return 0
    sed 's#@localhost:[0-9][0-9]*/#@rustrak:8080/#' config/rustrak_project.key
}
