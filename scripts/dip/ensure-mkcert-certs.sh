#!/usr/bin/env bash
# Ensure local TLS certs exist for running the preview stack behind Caddy.
# Invoked from dip.yml `provision:` task list.

set -eu

CERT_KEY=".dockerdev/caddy/certs/localhost-key.pem"
CERT_CRT=".dockerdev/caddy/certs/localhost-cert.pem"

if [[ ! -f "${CERT_KEY}" || ! -f "${CERT_CRT}" ]]; then
    echo
    echo "================================================================================"
    echo
    echo "Creating local TLS certs for running local production environment with Caddy."
    echo "If this errors you may need to install and set up mkcert."
    echo
    echo "================================================================================"
    echo
    mkcert -key-file "${CERT_KEY}" -cert-file "${CERT_CRT}" localhost
fi
