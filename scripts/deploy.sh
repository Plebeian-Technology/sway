#!/usr/bin/env zsh

set -eu

# Where this copy of Sway lives: the machine, its disk, the image store. None of
# it is written into this repository, which is public. See
# deploy/config/sway.env.example.
. "$(dirname "$0")/../deploy/config/load.sh"
sway_load_config
sway_require SWAY_REGISTRY SWAY_GCS_BUCKET_ASSETS

TARGET=""
SKIP_FILE_UPLOADS=0
NO_BUILD=0
INITIAL_DEPLOY=0

usage() {
    cat <<'USAGE'
Deploy Sway.

    ./scripts/deploy.sh [--target <name>] [--skip-file-upload] [--no-build] [--initial-deploy]

    --target <name>      Deploy to a practice machine instead of production.
                         Reads config/deploy.<name>.yml layered on top of
                         config/deploy.yml. There are no practice machines
                         today, so this has nothing to read until you add one.
    --skip-file-upload   Do not re-upload the map and seed files to cloud
                         storage. They rarely change and the upload is slow.
    --no-build           Do not build anything. Start the image that was
                         already built and uploaded for this commit, instead
                         of making a new one. Fails if there is no such image.
    --initial-deploy     Run a first-time production deploy (`kamal deploy`
                         instead of `kamal redeploy`), boot accessories instead
                         of rebooting them, and run initial bill seeding and
                         score backfills inside the web container. Defaults to
                         false.
    -h, --help           Show this and stop.

With no --target this deploys production, which is the normal case.

A --target also SKIPS three steps that act on production, because doing them
from a practice run would cause real damage. Each one says why at the point it
is skipped: the release tag, the accessory restarts, and the Litestream keyfile
push.

--no-build is for when the build already happened: `kamal build push` earlier,
or a deploy that got as far as uploading and then failed. It keeps the slow
part out of a maintenance window, and it guarantees the thing being started is
the thing that was tested, rather than a rebuild that might differ.

It does NOT tag a release, because the release number is decided when the image
is built and baked into it — a tag written now could name a different number
than the one the running app reports. Tag by hand if you want one.
USAGE
}

# Anything unrecognised stops the script. This deploys production by default, so
# a typo like `--taget spare` must not be quietly ignored and sent to the machine
# serving the public.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "deploy.sh: --target needs a name, e.g. --target spare" >&2
                exit 1
            fi
            TARGET="$2"
            shift 2
            ;;
        --target=*)
            TARGET="${1#--target=}"
            if [[ -z "$TARGET" ]]; then
                echo "deploy.sh: --target needs a name, e.g. --target=spare" >&2
                exit 1
            fi
            shift
            ;;
        --skip-file-upload|--skip-file-uploads)
            SKIP_FILE_UPLOADS=1
            shift
            ;;
        --no-build)
            NO_BUILD=1
            shift
            ;;
        --initial-deploy)
            INITIAL_DEPLOY=1
            shift
            ;;
        --initial-deploy=*)
            case "${1#--initial-deploy=}" in
                1|true)
                    INITIAL_DEPLOY=1
                    ;;
                0|false)
                    INITIAL_DEPLOY=0
                    ;;
                *)
                    echo "deploy.sh: --initial-deploy expects true or false (got '${1#--initial-deploy=}')" >&2
                    exit 1
                    ;;
            esac
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "deploy.sh: unknown argument '$1'" >&2
            echo "" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Catch a mistyped target here rather than letting kamal fail partway in, or —
# worse — letting a name with no config file behave like something it is not.
if [[ -n "$TARGET" && ! -f "config/deploy.$TARGET.yml" ]]; then
    echo "deploy.sh: no config/deploy.$TARGET.yml, so '--target $TARGET' has nothing to read." >&2
    # `find`, not a glob. zsh treats a pattern that matches nothing as an error
    # and prints "no matches found" over the top of the message below — which is
    # exactly the case this branch exists to handle.
    available="$(find config -maxdepth 1 -name 'deploy.*.yml' 2>/dev/null | sed 's#.*/deploy\.##; s#\.yml##' | sort)"
    if [[ -n "$available" ]]; then
        echo "           Available targets:" >&2
        printf '%s\n' "$available" | sed 's#^#             #' >&2
    else
        # An empty list under a heading reads as "none found today", which is
        # not the same as "this repository describes none". Say which it is.
        echo "           There are no practice machines. Sway has one machine and" >&2
        echo "           it serves the public, so every deploy goes there." >&2
    fi
    exit 1
fi

# @lat: [[deploy-rehearsal#Why a practice run cannot land on the machine serving the public]]
if [[ -n "$TARGET" ]]; then
    echo "deploy.sh -> Checking that '$TARGET' is not the machine serving the public"

    if ! live_config="$(kamal config 2>&1)"; then
        echo "deploy.sh: could not read the production settings, so the check below" >&2
        echo "           cannot be made. Stopping rather than guessing." >&2
        printf '%s\n' "$live_config" | sed 's/^/    /' >&2
        exit 1
    fi
    if ! practice_config="$(kamal config -d "$TARGET" 2>&1)"; then
        echo "deploy.sh: could not read the settings for '$TARGET'." >&2
        printf '%s\n' "$practice_config" | sed 's/^/    /' >&2
        exit 1
    fi

    printf '%s' "$live_config"     > "${TMPDIR:-/tmp}/sway-live-config.$$.yml"
    printf '%s' "$practice_config" > "${TMPDIR:-/tmp}/sway-practice-config.$$.yml"

    clash="$(ruby -ryaml -e '
        read = ->(p) { YAML.load(File.read(p), permitted_classes: [Symbol], aliases: true) }
        live, practice = read.(ARGV[0]), read.(ARGV[1])

        shared_machines = Array(live[:hosts]) & Array(practice[:hosts])
        store = ->(c) { Array(c[:volume_args]).grep(%r{:/rails/storage\z}) }
        shared_storage = store.(live) & store.(practice)

        say = []
        say << "the machine #{shared_machines.join(", ")}" unless shared_machines.empty?
        say << "the storage folder #{shared_storage.map { |v| v.split(":").first }.join(", ")}" unless shared_storage.empty?
        puts say.join(" and ")
    ' "${TMPDIR:-/tmp}/sway-live-config.$$.yml" "${TMPDIR:-/tmp}/sway-practice-config.$$.yml")"

    rm -f "${TMPDIR:-/tmp}/sway-live-config.$$.yml" "${TMPDIR:-/tmp}/sway-practice-config.$$.yml"

    if [[ -n "$clash" ]]; then
        echo "" >&2
        echo "#############################################################################" >&2
        echo "deploy.sh -> STOPPED. '$TARGET' is not a separate machine." >&2
        echo "#############################################################################" >&2
        echo "" >&2
        echo "  It shares $clash with the deploy that serves the public." >&2
        echo "" >&2
        echo "  Going on would start a second app beside the live one, on the same" >&2
        echo "  database file. A container runs migrations and seeds as it starts, so" >&2
        echo "  the live database would be written by two programs at once." >&2
        echo "" >&2
        echo "  Point the practice settings at a different machine with its own disk," >&2
        echo "  then run this again. See deploy/config/sway.env.example." >&2
        echo "" >&2
        exit 1
    fi

    echo "  ok: a different machine and a different storage folder"

    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> PRACTICE RUN on '$TARGET' — production is not touched"
    echo "#############################################################################"
    echo "  Skipping the release tag, the accessory restarts, and the Litestream"
    echo "  keyfile push. All three act on production."
fi

# Wall-clock bounds for the run, reported by the trap below. A trap rather than
# a few lines at the foot of the file because `set -e` never reaches the foot,
# and a deploy that died twelve minutes in is exactly when the elapsed time is
# worth knowing. The practice run's early `exit 0` is covered for free too.
#
# Started here, after argument checking, so `--help` and a mistyped flag stay
# silent — they did not deploy anything and have no duration worth printing.
#
# Two stamps, not one: the ISO one goes in the log beside the release's own
# SWAY_DEPLOYED_AT, and the epoch one is the only one arithmetic can use.
SWAY_DEPLOY_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SWAY_DEPLOY_STARTED_EPOCH="$(date +%s)"

# `exit_code` and not `status`: zsh's $status is a second name for $?, so a
# local of that name would shadow a special parameter.
sway_report_run_time() {
    local exit_code=$?
    local ended_at ended_epoch elapsed

    ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ended_epoch="$(date +%s)"
    elapsed=$((ended_epoch - SWAY_DEPLOY_STARTED_EPOCH))

    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> started $SWAY_DEPLOY_STARTED_AT"
    echo "deploy.sh -> ended   $ended_at"
    echo "deploy.sh -> took    $((elapsed / 60))m $((elapsed % 60))s (exit $exit_code)"
    echo "#############################################################################"
    echo ""
}
trap sway_report_run_time EXIT

# export $(cat .env.kamal | xargs)
# set -a
# source .env.kamal
# set +a

export $(cat .env.kamal | xargs)

# @lat: [[use-your-own-secret-store]]
source "$(dirname "$0")/lib/secrets.sh"
sway_secrets_unlock --sync

echo ""
echo "#############################################################################"
echo "deploy.sh -> RAILS_ENV=production bundle install"
echo "#############################################################################"
echo ""
RAILS_ENV=production bundle install

echo ""
echo "#############################################################################"
echo "deploy.sh -> RAILS_ENV=test install + rspec"
echo "#############################################################################"
echo ""
# RAILS_ENV=test bundle install
# RAILS_ENV=test bundle exec rspec

echo ""
echo "#############################################################################"
echo "deploy.sh -> Clobber rails assets so they don't get added to the docker build"
echo "#############################################################################"
echo ""
# SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:clobber
# RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:clobber

if [[ "$SKIP_FILE_UPLOADS" == 0 ]]; then
    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> Copy geojson files to google cloud gs://${SWAY_GCS_BUCKET_ASSETS}/"
    echo "#############################################################################"
    echo ""
    gcloud storage cp --recursive $(pwd)/storage/geojson gs://${SWAY_GCS_BUCKET_ASSETS}/

    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> Copy seed file data to google cloud gs://${SWAY_GCS_BUCKET_ASSETS}/seeds/"
    echo "#############################################################################"
    echo ""
    gcloud storage cp --recursive $(pwd)/db/seeds/data gs://${SWAY_GCS_BUCKET_ASSETS}/seeds/
fi

echo ""
echo "#############################################################################"
echo "deploy.sh -> Compute release metadata (SWAY release tracking)"
echo "#############################################################################"
echo ""

# These four values are exported so config/deploy.yml's `builder.args` ERB can
# thread them into the Docker build, where the Dockerfile bakes them into the
# image as ENV. Sway::Release reads them at runtime. The integer is the next
# `release-N` tag number; the tag itself is created + pushed only AFTER a
# successful deploy (below), so a failed deploy leaves the number unconsumed
# and the next attempt reuses it.
#
# Skipped entirely with --no-build. Nothing reads these except the build, so
# working them out would only print numbers that have no bearing on the image
# being started — and the most misleading thing a deploy can do is announce a
# release number that is not the one the app will report.
if [[ "$NO_BUILD" == 0 ]]; then
    git fetch --tags --quiet || true

    PREV_TAG="$(git tag --list 'release-*' --sort=-v:refname | head -n 1)"
    if [[ -n "$PREV_TAG" ]]; then
        PREV_VERSION="${PREV_TAG#release-}"
        PREV_SHA="$(git rev-list -n 1 "$PREV_TAG")"
    else
        PREV_VERSION=0
        PREV_SHA=""
    fi

    export SWAY_RELEASE_VERSION=$((PREV_VERSION + 1))
    export SWAY_RELEASE_SHA="$(git rev-parse HEAD)"
    export SWAY_PREVIOUS_SHA="$PREV_SHA"
    export SWAY_DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # @lat: [[system-shape#Deployment#The release fingerprint never runs a diff converter]]
    SWAY_UNCOMMITTED_DIGEST="$("$(dirname "$0")/uncommitted_digest.sh")"
    export SWAY_UNCOMMITTED_DIGEST

    echo "  release version : $SWAY_RELEASE_VERSION (previous tag: ${PREV_TAG:-<none>})"
    echo "  current sha     : $SWAY_RELEASE_SHA"
    echo "  previous sha    : ${SWAY_PREVIOUS_SHA:-<none>}"
    echo "  deployed at     : $SWAY_DEPLOYED_AT"
    if [[ -n "$SWAY_UNCOMMITTED_DIGEST" ]]; then
        echo "  working tree    : DIRTY (uncommitted digest $SWAY_UNCOMMITTED_DIGEST)"
        echo "                    this image cannot be rebuilt from the commit above"
    else
        echo "  working tree    : clean"
    fi
else
    echo "  skipped: --no-build starts an image that already exists, and its"
    echo "           release numbers were decided when it was built."
fi

echo ""
echo "#############################################################################"
echo "deploy.sh -> Provision Litestream GCS keyfile on the replication host"
echo "#############################################################################"
echo ""

# @lat: [[litestream-credential#Why the destination is read out of the deploy configuration]]
if [[ -z "$TARGET" ]]; then
    ./scripts/provision-litestream-key.sh
else
    echo "  skipped: practice run does not run Litestream."
fi

echo ""
echo "#############################################################################"
echo "deploy.sh -> Provision and deploy host sway-pdf-extractor"
echo "#############################################################################"
echo ""

# @lat: [[deploy-configuration#What the deploy file decides#Why PDF_EXTRACTOR_URL points at the host extractor port]]
if [[ -z "$TARGET" ]]; then
    sway_require SWAY_HOST SWAY_STORAGE_DIR
    PDF_EXTRACTOR_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
    if [[ -n "${SWAY_SSH_KEY:-}" ]]; then
        PDF_EXTRACTOR_SSH_OPTS+=(-i "${SWAY_SSH_KEY/#\~/$HOME}" -o IdentitiesOnly=yes)
    fi

    provision_host_pdf_extractor() {
        local admin_ssh_key admin_ssh_opts admin_host
        admin_ssh_key="${SWAY_ADMIN_SSH_KEY:-$HOME/.ssh/sway_deploy}"
        admin_ssh_key="${admin_ssh_key/#\~/$HOME}"
        admin_ssh_opts=(-o ConnectTimeout=10)
        if [[ -f "$admin_ssh_key" ]]; then
            admin_ssh_opts+=(-i "$admin_ssh_key" -o IdentitiesOnly=yes)
        fi
        admin_host="${SWAY_ADMIN_USER:+$SWAY_ADMIN_USER@}$SWAY_HOST"
        ssh "${admin_ssh_opts[@]}" "$admin_host" 'cat > /tmp/sway-provision-pi.sh && chmod 0700 /tmp/sway-provision-pi.sh' < ./scripts/provision-pi.sh \
            && ssh -t "${admin_ssh_opts[@]}" "$admin_host" "sudo SWAY_PI_DEPLOY_USER='${SWAY_DEPLOY_USER:-kamal}' SWAY_PI_STORAGE_DIR='$SWAY_STORAGE_DIR' bash /tmp/sway-provision-pi.sh pdf-extractor; rc=\$?; rm -f /tmp/sway-provision-pi.sh; exit \$rc"
    }

    check_host_pdf_extractor_prereqs() {
        ssh "${PDF_EXTRACTOR_SSH_OPTS[@]}" "${SWAY_DEPLOY_USER:-kamal}@$SWAY_HOST" 'command -v tesseract >/dev/null 2>&1 && command -v mutool >/dev/null 2>&1 && test -f /usr/share/tesseract-ocr/5/tessdata/eng.traineddata && test -f /etc/systemd/system/sway-pdf-extractor.service && test -f /etc/systemd/system/sway-pdf-extractor.path && test -f /etc/systemd/system/sway-pdf-extractor-restart.service && grep -F -q "PathChanged=$HOME/bin/sway-pdf-extractor" /etc/systemd/system/sway-pdf-extractor.path && grep -F -q "ExecStart=$HOME/bin/sway-pdf-extractor" /etc/systemd/system/sway-pdf-extractor.service && grep -q "^User=100$" /etc/systemd/system/sway-pdf-extractor.service && grep -q "^Group=101$" /etc/systemd/system/sway-pdf-extractor.service && grep -q "^StartLimitIntervalSec=0$" /etc/systemd/system/sway-pdf-extractor.service && grep -q "^StartLimitIntervalSec=0$" /etc/systemd/system/sway-pdf-extractor.path && grep -q "^StartLimitIntervalSec=0$" /etc/systemd/system/sway-pdf-extractor-restart.service && grep -F -q '\''Environment="PDF_EXTRACTOR_ALLOWED_ROOT='"$SWAY_STORAGE_DIR"'"'\'' /etc/systemd/system/sway-pdf-extractor.service && systemctl is-active --quiet sway-pdf-extractor.path && test -d "$HOME/bin"'
    }

    TMP_PDF_EXTRACTOR="$(mktemp "${TMPDIR:-/tmp}/sway-pdf-extractor.XXXXXX")"
    (cd ops/pdf-extractor && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o "$TMP_PDF_EXTRACTOR" .) || { rm -f "$TMP_PDF_EXTRACTOR"; exit 1; }

    if ! check_host_pdf_extractor_prereqs; then
        echo "  host prerequisites missing on $SWAY_HOST; provisioning pdf-extractor via sudoers SSH key..."
        provision_host_pdf_extractor || { rm -f "$TMP_PDF_EXTRACTOR"; exit 1; }
        if ! check_host_pdf_extractor_prereqs; then
            rm -f "$TMP_PDF_EXTRACTOR"
            echo "deploy.sh: sway-pdf-extractor host prerequisites still missing on $SWAY_HOST after provisioning" >&2
            exit 1
        fi
    fi

    if ! ssh "${PDF_EXTRACTOR_SSH_OPTS[@]}" "${SWAY_DEPLOY_USER:-kamal}@$SWAY_HOST" 'cat > "$HOME/bin/sway-pdf-extractor.tmp" && chmod 0755 "$HOME/bin/sway-pdf-extractor.tmp" && mv -f "$HOME/bin/sway-pdf-extractor.tmp" "$HOME/bin/sway-pdf-extractor"' < "$TMP_PDF_EXTRACTOR"; then
        rm -f "$TMP_PDF_EXTRACTOR"
        exit 1
    fi
    rm -f "$TMP_PDF_EXTRACTOR"

    wait_for_host_pdf_extractor() {
        for _ in {1..10}; do
            if ssh "${PDF_EXTRACTOR_SSH_OPTS[@]}" "${SWAY_DEPLOY_USER:-kamal}@$SWAY_HOST" 'curl -fsS --max-time 2 http://127.0.0.1:8085/up >/dev/null 2>&1'; then
                return 0
            fi
            sleep 1
        done
        return 1
    }

    PDF_EXTRACTOR_HEALTHY=0
    if wait_for_host_pdf_extractor; then
        PDF_EXTRACTOR_HEALTHY=1
    else
        echo "  sway-pdf-extractor did not respond on 127.0.0.1:8085; re-provisioning and restarting via sudoers SSH key..."
        if provision_host_pdf_extractor && wait_for_host_pdf_extractor; then
            PDF_EXTRACTOR_HEALTHY=1
        fi
    fi
    if [[ "$PDF_EXTRACTOR_HEALTHY" != 1 ]]; then
        ssh "${PDF_EXTRACTOR_SSH_OPTS[@]}" "${SWAY_DEPLOY_USER:-kamal}@$SWAY_HOST" 'systemctl status sway-pdf-extractor.path sway-pdf-extractor-restart.service sway-pdf-extractor.service --no-pager -l 2>&1 || true' >&2
        echo "deploy.sh: sway-pdf-extractor failed health check at http://127.0.0.1:8085/up on $SWAY_HOST" >&2
        exit 1
    fi
else
    echo "  skipped: practice run does not deploy host sway-pdf-extractor."
fi

echo ""
echo "#############################################################################"
echo "deploy.sh -> Probe for active Tailscale mesh IP"
echo "#############################################################################"
echo ""

# @lat: [[deploy-configuration#What the deploy file decides#Why the monitoring accessories are capped and bound to private addresses]]
if [[ -z "${SWAY_TAILSCALE_IP:-}" && -z "$TARGET" ]]; then
    echo "deploy.sh -> Probing for active Tailscale on $SWAY_HOST..."
    PROBED_TS_IP=""
    CGNAT_REGEX="^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}$"

    LOCAL_TS_IP=""
    if command -v tailscale >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            if timeout 2 tailscale status --peers=false >/dev/null 2>&1; then
                LOCAL_TS_IP="$(timeout 2 tailscale ip -4 2>/dev/null || true)"
            fi
        elif perl -e 'alarm 2; exec @ARGV' tailscale status --peers=false >/dev/null 2>&1; then
            LOCAL_TS_IP="$(perl -e 'alarm 2; exec @ARGV' tailscale ip -4 2>/dev/null || true)"
        fi
    fi

    if [[ "$LOCAL_TS_IP" =~ $CGNAT_REGEX ]]; then
        SSH_PROBE_OPTS=(-o BatchMode=yes -o ConnectTimeout=2)
        if [[ -n "${SWAY_SSH_KEY:-}" ]]; then
            SSH_PROBE_OPTS+=(-i "${SWAY_SSH_KEY/#\~/$HOME}" -o IdentitiesOnly=yes)
        fi
        REMOTE_TS_IP="$(ssh "${SSH_PROBE_OPTS[@]}" "${SWAY_DEPLOY_USER:-kamal}@$SWAY_HOST" "timeout 2 tailscale status --peers=false >/dev/null 2>&1 && timeout 2 tailscale ip -4 2>/dev/null" 2>/dev/null || true)"
        if [[ "$REMOTE_TS_IP" =~ $CGNAT_REGEX ]]; then
            PROBED_TS_IP="$REMOTE_TS_IP"
        fi
    fi

    if [[ -n "$PROBED_TS_IP" ]]; then
        export SWAY_TAILSCALE_IP="$PROBED_TS_IP"
        echo "  detected active Tailscale IP: $SWAY_TAILSCALE_IP"
    else
        echo "  Tailscale not active on both hosts; falling back to LAN-only SWAY_HOST ($SWAY_HOST)."
    fi
else
    if [[ -n "${SWAY_TAILSCALE_IP:-}" ]]; then
        echo "  using configured SWAY_TAILSCALE_IP: $SWAY_TAILSCALE_IP"
    else
        echo "  skipped: practice run does not probe Tailscale."
    fi
fi

echo ""
echo "#############################################################################"
echo "deploy.sh -> Kamal Deploy."
echo "#############################################################################"
echo ""

# Kamal's local builder uses the docker-container driver, which spawns a
# buildkit container with its own daemon — that daemon does NOT inherit
# Docker Desktop's insecure-registries config. Without this, a push to the
# image store over plain HTTP fails with "server gave HTTP response to HTTPS
# client", which blames encryption for what is really a missing permission. We provision the builder once with a buildkitd.toml
# that flags the registry as HTTP/insecure; the config is baked into the
# buildkit container on creation.
#
# Idempotent: re-creating the builder every deploy would wipe BuildKit's
# cache mounts (apk/bundler/pnpm caches from the Dockerfile), so we only
# create when missing. To force-rebuild after changing the config or
# registry hostname:
#
#     docker buildx rm kamal-local-docker-container
#
# and re-run this script.
if ! docker buildx inspect kamal-local-docker-container >/dev/null 2>&1; then
    # Unquoted heredoc on purpose: the store's address has to be substituted.
    cat > /tmp/kamal-buildkitd.toml <<EOF
[registry."${SWAY_REGISTRY}"]
http = true
insecure = true
EOF

    echo "deploy.sh -> building local kamal docker container."

    docker buildx create \
        --name kamal-local-docker-container \
        --driver docker-container \
        --config /tmp/kamal-buildkitd.toml \
        --bootstrap

    rm /tmp/kamal-buildkitd.toml
else
    echo "deploy.sh -> skip building local kamal docker container."
fi

# Production uses `redeploy`, which is `deploy` minus starting kamal-proxy and
# minus pruning old images — both already done, and skipping them keeps a routine
# deploy short.
#
# A practice run uses full `deploy`, because kamal-proxy has never been started on
# a new machine and `redeploy` would leave the container with nothing in front of
# it to route requests.
#
# A practice file MUST name the extra services as its own machine. Kamal's last
# step prunes old images and stopped containers on EVERY machine named anywhere
# in the merged settings, not only the ones being deployed to — so a practice
# file that leaves them inherited would delete production's older images, which
# are exactly what `kamal rollback` needs there.
#
# --no-build becomes kamal's `-P`, which is spelled "skip push" and reads like
# it only skips the upload. It skips the build as well: kamal pulls the image
# already sitting in the store instead of making one. That name is why this
# script offers a plainer one.
BUILD_ARGS=()
if [[ "$NO_BUILD" == 1 ]]; then
    BUILD_ARGS+=(-P)
    echo "  --no-build: starting the image already built for this commit."
fi

# @lat: [[troubleshoot-deploys#No route to host (EHOSTUNREACH)]]
export BUILDKIT_PROGRESS="${BUILDKIT_PROGRESS:-plain}"
export SSHKIT_COLOR="${SSHKIT_COLOR:-1}"
LOG_FILE=$(mktemp)
set -o pipefail

if [[ -n "$TARGET" ]]; then
    if ! kamal deploy -d "$TARGET" "${BUILD_ARGS[@]}" --verbose 2>&1 | tee "$LOG_FILE"; then
        if grep -q "ERROR (Errno::EHOSTUNREACH)" "$LOG_FILE"; then
            echo ""
            echo "=============================================================================="
            echo "DEPLOY FAILED: No route to host (EHOSTUNREACH)"
            echo "Your macOS routing table or firewall extension may have stale connections."
            echo ""
            echo "To flush stale VPN connections, run your VPN's down/up commands, for example:"
            echo "  sudo tailscale down && sudo tailscale up"
            echo ""
            echo "Alternatively, fully quit your VPN client and toggle Wi-Fi off and on, or"
            echo "restart your computer, then try again."
            echo "=============================================================================="
            echo ""
        fi
        rm -f "$LOG_FILE"
        exit 1
    fi
elif [[ "$INITIAL_DEPLOY" == 1 ]]; then
    if ! kamal deploy "${BUILD_ARGS[@]}" --verbose 2>&1 | tee "$LOG_FILE"; then
        if grep -q "ERROR (Errno::EHOSTUNREACH)" "$LOG_FILE"; then
            echo ""
            echo "=============================================================================="
            echo "DEPLOY FAILED: No route to host (EHOSTUNREACH)"
            echo "Your macOS routing table or firewall extension may have stale connections."
            echo ""
            echo "To flush stale VPN connections, run your VPN's down/up commands, for example:"
            echo "  sudo tailscale down && sudo tailscale up"
            echo ""
            echo "Alternatively, fully quit your VPN client and toggle Wi-Fi off and on, or"
            echo "restart your computer, then try again."
            echo "=============================================================================="
            echo ""
        fi
        rm -f "$LOG_FILE"
        exit 1
    fi
else
    if ! kamal redeploy "${BUILD_ARGS[@]}" --verbose 2>&1 | tee "$LOG_FILE"; then
        if grep -q "ERROR (Errno::EHOSTUNREACH)" "$LOG_FILE"; then
            echo ""
            echo "=============================================================================="
            echo "DEPLOY FAILED: No route to host (EHOSTUNREACH)"
            echo "Your macOS routing table or firewall extension may have stale connections."
            echo ""
            echo "To flush stale VPN connections, run your VPN's down/up commands, for example:"
            echo "  sudo tailscale down && sudo tailscale up"
            echo ""
            echo "Alternatively, fully quit your VPN client and toggle Wi-Fi off and on, or"
            echo "restart your computer, then try again."
            echo "=============================================================================="
            echo ""
        fi
        rm -f "$LOG_FILE"
        exit 1
    fi
fi
rm -f "$LOG_FILE"

# Everything from here is production-only.
#
# The release tag must not be created by a practice run. The number is what
# Sway::Release reports in the app, and the next production deploy reads the tag
# back to work out which release came before it — so tagging from a practice run
# would make the next real deploy believe the practice one was production. Not
# tagging leaves the number unclaimed, which is the same thing that happens when a
# deploy fails, and the next attempt reuses it.
#
# The accessory restarts must not happen either. With a destination they would act
# on the practice machine: a second Litestream copying to the same place in cloud
# storage corrupts the history, and a second cloudflared would start pulling real
# public traffic to a machine running a database built from seeds.
if [[ -n "$TARGET" ]]; then
    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> Practice run finished. No tag, no accessory restarts."
    echo "#############################################################################"
    echo ""
    exit 0
fi

# Deploy succeeded (set -e would have aborted otherwise). Record the release:
# tag the deployed SHA with the integer version and push the tag to origin so
# the next deploy reads it back as the previous release.
#
# Not with --no-build. The number lives inside the image, put there when it was
# built, and that is what the running app reports. Working out a fresh number
# here would write a tag saying this commit shipped as release N while the app
# says something else — and the tag is what the NEXT deploy reads to decide its
# own number, so one wrong tag misnumbers everything after it.
if [[ "$NO_BUILD" == 1 ]]; then
    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> No release tag: --no-build did not create this image."
    echo "#############################################################################"
    echo "  The release number is inside the image already. Tag by hand if you want"
    echo "  one, using the number the app reports on /version."
    echo ""
else
    echo ""
    echo "#############################################################################"
    echo "deploy.sh -> Tag release-$SWAY_RELEASE_VERSION and push"
    echo "#############################################################################"
    echo ""
    git tag -a "release-$SWAY_RELEASE_VERSION" "$SWAY_RELEASE_SHA" \
        -m "Release $SWAY_RELEASE_VERSION — $SWAY_DEPLOYED_AT — $SWAY_RELEASE_SHA"
    git push origin "release-$SWAY_RELEASE_VERSION"
fi

if [[ "$INITIAL_DEPLOY" == 1 ]]; then
    kamal accessory boot cloudflare_tunnel --verbose
    kamal accessory boot litestream --verbose
    kamal accessory boot beszel --verbose
    kamal accessory boot beszel_agent --verbose
    kamal accessory boot auditd --verbose

    bundle exec rails db:seed
    bundle exec rails db:seed:bills
    bundle exec rails sway:backfill:legislator_locale_scores
else # re-deploy
    kamal accessory reboot cloudflare_tunnel --verbose

    # @lat: [[litestream-credential#Why the accessory is restarted after each deploy]]
    kamal accessory reboot litestream --verbose

    kamal accessory reboot beszel --verbose
    kamal accessory reboot beszel_agent --verbose
    kamal accessory reboot auditd --verbose
fi
