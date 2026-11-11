#!/usr/bin/env bash
# @lat: [[use-your-own-secret-store]]

SWAY_SECRETS_ACCOUNT_PLACEHOLDER="SWAY_SECRETS_ACCOUNT-is-not-set"

sway_secrets_adapter() {
    printf '%s\n' "${SWAY_SECRETS_ADAPTER:-bitwarden}"
}

sway_secrets_account() {
    if [ -n "${SWAY_SECRETS_ACCOUNT:-}" ]; then
        printf '%s\n' "$SWAY_SECRETS_ACCOUNT"
    elif [ "$(sway_secrets_adapter)" = "bitwarden" ]; then
        printf '%s\n' "${SWAY_BW_ACCOUNT:-}"
    fi
}

# @lat: [[settings-and-secrets#Secret store settings]]
sway_secrets_requires_account() {
    case "$1" in
        aws_secrets_manager | bitwarden-sm | bitwarden_secrets_manager | doppler | enpass | passbolt | env) return 1 ;;
        *) return 0 ;;
    esac
}

sway_secrets_kamal_options() {
    local adapter account
    adapter="$(sway_secrets_adapter)"
    account="$(sway_secrets_account)"

    printf '%s\n' --adapter "$adapter"
    if [ -n "$account" ]; then
        printf '%s\n' --account "$account"
    elif sway_secrets_requires_account "$adapter"; then
        echo "secrets: $adapter needs an account. Set SWAY_SECRETS_ACCOUNT in .env.kamal." >&2
        printf '%s\n' --account "$SWAY_SECRETS_ACCOUNT_PLACEHOLDER"
    fi
    if [ -n "${SWAY_SECRETS_FROM:-}" ]; then
        printf '%s\n' --from "$SWAY_SECRETS_FROM"
    fi
}

sway_secrets_unlock() {
    case "$(sway_secrets_adapter)" in
        bitwarden)
            if [[ -z "${BW_SESSION:-}" ]] || ! bw status 2>/dev/null | grep -q '"status":[[:space:]]*"unlocked"'; then
                BW_SESSION="$(bw unlock --raw)" || return 1
                export BW_SESSION
            fi
            if [ "${1:-}" = "--sync" ]; then
                bw sync || return 1
            fi
            ;;
    esac
}

sway_secrets_fetch() {
    if [ "$(sway_secrets_adapter)" = "env" ]; then
        ruby -rjson -e '
            missing = ARGV.select { |name| ENV[name].to_s.empty? }
            abort("secrets: env adapter: #{missing.join(" ")} unset or empty") unless missing.empty?
            print JSON.dump(ARGV.map { |name| [name, ENV[name]] }.to_h)
        ' -- "$@"
        return
    fi

    local options=() option
    while IFS= read -r option; do
        options+=("$option")
    done < <(sway_secrets_kamal_options)
    kamal secrets fetch "${options[@]}" "$@"
}

sway_secrets_extract() {
    kamal secrets extract "$1" "$2"
}

sway_secrets_get() {
    local item="$1" json
    case "$(sway_secrets_adapter)" in
        bitwarden)
            bw get password "$item"
            ;;
        env)
            [ -n "$(printenv "$item")" ] || { echo "secrets: env adapter: $item unset or empty" >&2; return 1; }
            printenv "$item"
            ;;
        *)
            json="$(sway_secrets_fetch "$item")" || return 1
            sway_secrets_extract "$item" "$json"
            ;;
    esac
}

# @lat: [[kamal-vault-account-indirection#Why the helper prints the fetch command instead of running it]]
sway_secrets_fetch_command() {
    if [ "$(sway_secrets_adapter)" = "env" ]; then
        echo "bash scripts/lib/secrets.sh fetch-inline"
        return
    fi
    local words
    words="$(sway_secrets_kamal_options | tr '\n' ' ')"
    echo "kamal secrets fetch ${words% }"
}

sway_secrets_fetch_inline() {
    local json
    if json="$(sway_secrets_fetch "$@")"; then
        printf '%s' "$json" | ruby -rshellwords -e 'print $stdin.read.shellescape'
    else
        printf '%s' "sway-secrets-fetch-failed"
        return 1
    fi
}

if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    command="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$command" in
        fetch-command) sway_secrets_fetch_command ;;
        fetch-inline) sway_secrets_fetch_inline "$@" ;;
        fetch) sway_secrets_fetch "$@" ;;
        get) sway_secrets_get "$1" ;;
        unlock) sway_secrets_unlock "$@" ;;
        *)
            echo "usage: $0 <fetch-command|fetch-inline|fetch|get|unlock> [ITEM...]" >&2
            exit 2
            ;;
    esac
fi
