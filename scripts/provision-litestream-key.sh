#!/usr/bin/env bash
#
# Push the Litestream GCS service-account keyfile to one or more hosts.
# Called by scripts/deploy.sh; also runnable standalone when
# provisioning a new Pi or rotating the credential.
#
#   scripts/provision-litestream-key.sh                     # writer -> the serving machine
#   scripts/provision-litestream-key.sh --reader <machine>  # read-only key -> a standby
#   scripts/provision-litestream-key.sh --print-target      # say where it would go, send nothing
#
# @lat: [[litestream-credential#Why the key has to be a file on the host]]

set -euo pipefail

# @lat: [[litestream-credential#Two accounts, and they are not interchangeable]]
BW_ITEM_WRITER="LITESTREAM_GCS_SERVICE_ACCOUNT_JSON"
BW_ITEM_READER="LITESTREAM_GCS_READER_JSON"
BW_ITEM="$BW_ITEM_WRITER"

cd "$(git rev-parse --show-toplevel)"

fail() { echo "provision-litestream-key: $1" >&2; exit 1; }

# @lat: [[litestream-credential#Why the destination is read out of the deploy configuration]]
read_deploy_config() {
    ruby -ryaml -rerb -e '
        c = YAML.load(ERB.new(File.read("config/deploy.yml")).result, aliases: true)
        a = c.dig("accessories", "litestream") or abort("no accessories.litestream in config/deploy.yml")
        vol = Array(a["volumes"]).find { |v| v.include?("gcs-key.json") }
        abort("no gcs-key.json volume on accessories.litestream") if vol.nil?
        puts a["host"].to_s
        puts(c.dig("ssh", "user") || "root")
        puts Array(c.dig("ssh", "keys")).first.to_s
        puts vol.split(":").first
    '
}

{ read -r DEPLOY_HOST; read -r SSH_USER; read -r SSH_KEY; read -r REMOTE_PATH; } < <(read_deploy_config)

[[ -n "${SSH_USER:-}"    ]] || fail "could not resolve ssh.user from config/deploy.yml"
[[ -n "${REMOTE_PATH:-}" ]] || fail "could not resolve the keyfile path from config/deploy.yml"

PRINT_ONLY=0
READER=0
WRITER_ASKED_FOR=0   # --writer was typed, so the guard below steps aside

while [[ $# -gt 0 ]]; do
    case "$1" in
        --print-target) PRINT_ONLY=1; shift ;;
        --reader)       READER=1; BW_ITEM="$BW_ITEM_READER"; shift ;;
        --writer)       READER=0; WRITER_ASKED_FOR=1; BW_ITEM="$BW_ITEM_WRITER"; shift ;;
        -*)             fail "unknown option '$1'. Use --reader, --writer or --print-target." ;;
        *)              break ;;
    esac
done

if [[ $# -gt 0 ]]; then
    HOSTS=("$@")
else
    # The read-only key belongs to the standby, and the standby is deliberately
    # NOT in config/deploy.yml — nothing deploys to it. So there is no machine to
    # fall back to, and guessing would send a credential somewhere nobody asked
    # for. Name it.
    [[ "$READER" == 0 ]] || fail "--reader needs the machine named: $0 --reader <machine>"
    [[ -n "${DEPLOY_HOST:-}" ]] || fail "no accessories.litestream.host in config/deploy.yml"
    HOSTS=("$DEPLOY_HOST")
fi

# Refuse to hand the deleting key to a machine that was named by hand. The one
# machine that should have it is the one config/deploy.yml already points at, so
# an explicitly named host plus the writer key is almost always a slip — and the
# cost of that slip is a second machine able to erase the only offsite copy.
if [[ "$READER" == 0 && "$WRITER_ASKED_FOR" == 0 && $# -gt 0 ]]; then
    for host in "$@"; do
        [[ "$host" == "${DEPLOY_HOST:-}" ]] || fail \
            "refusing to send the WRITER key (which can delete backups) to '$host', which is not the machine in config/deploy.yml. Use --reader for a standby, or --writer explicitly if you really mean it."
    done
fi

# Say where the credential would go and stop, touching neither the secret store nor any
# machine. Worth having on its own — this is a credential, and being able to ask
# "where would this go" before sending it is cheap. It also gives the test
# something to check, so the ERB mistake above cannot come back unnoticed.
if [[ "$PRINT_ONLY" == 1 ]]; then
    for host in "${HOSTS[@]}"; do
        echo "$SSH_USER@$host:$REMOTE_PATH"
    done
    exit 0
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
if [[ -n "${SSH_KEY:-}" ]]; then
    SSH_OPTS+=(-i "${SSH_KEY/#\~/$HOME}" -o IdentitiesOnly=yes)
fi

# @lat: [[use-your-own-secret-store]]
source scripts/lib/secrets.sh
sway_secrets_unlock || fail "could not unlock the $(sway_secrets_adapter) secret store"

KEY_JSON="$(sway_secrets_get "$BW_ITEM")" || fail "could not read '$BW_ITEM' from the $(sway_secrets_adapter) secret store"
[[ -n "$KEY_JSON" ]] || fail "'$BW_ITEM' is empty in the $(sway_secrets_adapter) secret store"

# Validate before shipping. A truncated or wrong-field paste would otherwise
# deploy silently and only surface later as an auth failure in the replicator,
# which is exactly the failure mode this whole issue has been chasing.
printf '%s' "$KEY_JSON" | ruby -rjson -e '
    k = JSON.parse($stdin.read)
    %w[type project_id private_key client_email].each do |f|
        abort("keyfile is missing #{f}") if k[f].to_s.empty?
    end
    abort("keyfile type is #{k["type"].inspect}, expected \"service_account\"") unless k["type"] == "service_account"
    warn "  keyfile looks valid: #{k["client_email"]} (project #{k["project_id"]})"
' || fail "'$BW_ITEM' is not a valid service-account keyfile"

REMOTE_DIR="$(dirname "$REMOTE_PATH")"

for host in "${HOSTS[@]}"; do
    echo "  -> $SSH_USER@$host:$REMOTE_PATH"

    # umask 077 first so the directory is 0700 and the file is created 0600 —
    # there is never a window in which the credential is world-readable.
    printf '%s' "$KEY_JSON" | ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" \
        "umask 077 \
         && mkdir -p '$REMOTE_DIR' \
         && cat > '$REMOTE_PATH' \
         && chmod 600 '$REMOTE_PATH'" \
        || fail "failed to write $REMOTE_PATH on $host"

    # Read back mode/owner/size — never contents — so a silent partial write
    # cannot pass as success.
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$host" \
        "stat -c '     verified: mode=%a owner=%U:%G bytes=%s' '$REMOTE_PATH'" \
        || fail "wrote $REMOTE_PATH on $host but could not stat it back"
done

echo "provision-litestream-key: done."
