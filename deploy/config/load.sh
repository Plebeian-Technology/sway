# Shared by every shell script that needs to know where this copy of Sway
# lives. Source it, do not run it:
#
#     . "$(dirname "$0")/../deploy/config/load.sh"
#     sway_load_config
#     sway_require SWAY_HOST SWAY_STORAGE_DIR
#
# It reads the same file, in the same order, as lib/sway_deploy_config.rb:
#
#   1. an environment variable already set — always wins, never overwritten
#   2. deploy/config/sway.env, which git ignores
#   3. nothing — sway_require then stops the script and names the value
#
# Nothing is guessed. A guessed address sends a deploy to the wrong machine,
# and a guessed bucket name uploads backups where nobody will look for them.
#
# WORKS IN BOTH bash AND zsh, because scripts/deploy.sh is zsh and the rest are
# bash. That rules out two things it would otherwise use: ${BASH_SOURCE[0]},
# which zsh does not set, and ${!name} indirect expansion, whose zsh spelling
# is ${(P)name}. `eval` covers both, and the repository root is found by
# walking up from the working directory rather than from this file's path.

# Prints the repository root, or nothing when it cannot be found.
sway_config_root() {
    local dir
    dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/lib/sway_deploy_config.rb" ]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Puts values from the file into the environment, skipping any name that
# already has one. Silent and harmless when the file does not exist — every
# value may legitimately come from the environment instead.
sway_load_config() {
    local root file line name value current

    if [ -n "${SWAY_DEPLOY_CONFIG_FILE:-}" ]; then
        file="$SWAY_DEPLOY_CONFIG_FILE"
    else
        root="$(sway_config_root)" || return 0
        if [ "${RAILS_ENV:-}" = "test" ]; then
            # Same rule as lib/sway_deploy_config.rb. A script run from the
            # test suite must read the tracked fake values, never the
            # operator's own file, or the suite behaves differently on every
            # machine.
            file="$root/deploy/config/sway.test.env"
        else
            file="$root/deploy/config/sway.env"
        fi
    fi

    [ -f "$file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        # Trim both ends, then drop blank lines and comments.
        line="${line# }"
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in "" | "#"*) continue ;; esac

        line="${line#export }"
        name="${line%%=*}"
        # No "=" on the line means %%=* handed back the whole line.
        [ "$name" = "$line" ] && continue
        value="${line#*=}"

        # One matching pair of quotes is wrapping, not content. A path with a
        # space in it needs them.
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac

        # Already set in the environment wins. This is what makes
        # SWAY_HOST=... ./scripts/deploy.sh work.
        eval "current=\${$name:-}"
        if [ -z "$current" ]; then
            export "$name=$value"
        fi
    done < "$file"
}

# Stops the script unless every named value has one. Names all the missing
# ones rather than only the first, so a half-filled file takes one round trip
# to fix instead of five.
sway_require() {
    local name current missing

    missing=""
    for name in "$@"; do
        eval "current=\${$name:-}"
        [ -z "$current" ] && missing="$missing $name"
    done

    [ -z "$missing" ] && return 0

    {
        echo
        echo "Sway does not know these values:"
        echo
        for name in $missing; do echo "  $name"; done
        echo
        echo "They are looked for in this order:"
        echo "  1. an environment variable of that name"
        echo "  2. deploy/config/sway.env"
        echo "  3. nothing — which is where this stopped"
        echo
        echo "Set one for a single run, for example:"
        echo
        for name in $missing; do
            echo "    $name=... $(basename "$0")"
            break
        done
        echo
        echo "or write your own values once:"
        echo
        echo "    cp deploy/config/sway.env.example deploy/config/sway.env"
        echo "    # then edit deploy/config/sway.env"
        echo
        echo "That file is ignored by git on purpose. It holds the addresses"
        echo "and account names belonging to your installation and no other."
        echo
    } >&2

    exit 1
}
