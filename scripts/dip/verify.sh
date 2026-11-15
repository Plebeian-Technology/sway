#!/usr/bin/env bash
# Run the full regression gate. Invoked from dip.yml `verify:` interaction.
#
# Runs on the HOST, not in a service: like scripts/dip/rspec.sh, it starts
# host lanes directly and shells into `dip compose run` for Docker lanes —
# the collector addresses must be set in the shell that calls
# `dip compose`, which is the same reason rspec.sh has no service: key.
# Takes no arguments; it always runs the whole gate.
#
# @lat: [[parallel-verification-gate#What running the lanes at once saves]]

set -eu

# dip appends arguments, and each Docker lane's command is fixed, so an
# argument here cannot reach any lane. Refuse rather than silently ignore it.
if [ "$#" -gt 0 ]; then
    echo "dip run verify takes no arguments — it runs the whole regression gate." >&2
    echo "For focused work, use:" >&2
    echo "    dip run rspec" >&2
    echo "    dip run bundle exec rspec <file>" >&2
    exit 64
fi

# @lat: [[parallel-verification-gate#Why the environment shim runs before any lane]]
scripts/dip/secrets-root.sh

# Compose interpolates the WHOLE file before it picks a service, so variables
# belonging to services no lane here starts — the preview app and the two
# Cloudflare tunnels — print an "is not set" warning on every run, five lines
# ahead of the gate's own output. Resolving them to empty is what dev.sh
# already does for the tunnel it skips. Empty is safe for the master key:
# Rails reads that one with .presence and falls back to config/master.key,
# which is how the rspec containers get it either way.
export CLOUDFLARED_DEV_TOKEN="${CLOUDFLARED_DEV_TOKEN:-}"
export CLOUDFLARED_PREVIEW_TOKEN="${CLOUDFLARED_PREVIEW_TOKEN:-}"
export RAILS_MASTER_KEY="${RAILS_MASTER_KEY:-}"

# How a finished lane is judged, in a file with no side effects so a test can
# call it with fixture values rather than grep this script for the shape of an
# if-chain. Repo-root-relative, the same way rustrak.sh is sourced below: dip
# runs this script from the repo root.
. scripts/dip/verify-lib.sh

RUN_ID="$$-$(date +%s)"
export RUN_ID
STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RUN_DIR="tmp/verify/$RUN_ID"
mkdir -p "$RUN_DIR"

# One append-only line per thing that starts or finishes, stamped with elapsed
# seconds. There is no live status board because a board redraws and
# degrades in a non-TTY; a plain line does neither, and reads the same in a
# terminal, in a pipe and in a captured agent log. Lane OUTPUT stays off
# screen too: a lane's own words stay in its own log and
# only the fact that it ended comes here.
#
# The decision assumed the reader is a subagent that wants summary.json. A
# person watching has no way to tell a working gate from a hung one across the
# barriers and the multi-minute lanes, which is minutes of silence before this
# existed. Stderr, so redirecting stdout to a file still shows progress.
progress() {
    printf '[%4ss] %s\n' "$SECONDS" "$*" >&2
}

# --- Sweep stale containers before any lane starts --------------------
# Nothing survives SIGKILL, so cleanup-on-exit below is best-effort and this
# sweep is the only reliable half. Two runs must both stay valid (no
# lock), so every removal here is age-gated. The gates are long enough for an
# ordinary run, not for every run: on one longer than an hour, a second run
# can remove a finished lane's container before the first run has read it.
# That costs the out-of-memory flag in summary.json and nothing else — the
# lane's exit code comes from `wait`, and a lane killed for memory exits 137,
# which already reports did-not-complete.
#
#   - EXITED: no lane carries --rm any more, so a finished lane's container
#     stays until its own run's cleanup fires at the very end. Removing it
#     would take away the out-of-memory flag that run is about to read.
#   - CREATED: not swept at all. That state lasts milliseconds while another
#     run is starting a lane, and there is no timestamp that distinguishes it
#     from one a SIGKILL abandoned. The cost is that an abandoned one is left
#     behind; it holds no CPU and no memory, only a little disk.
#   - RUNNING: someone else's lane, unless it is older than any run can be.
#
# 4 hours for a running container: 2.8x the slowest full run ever observed
# here (86 minutes). 1 hour for an exited one: longer than every full run but
# that outlier, which is the residual case above. Named rather than written
# into the comparisons, so the numbers a reader reasons about and the numbers
# the code uses cannot drift apart.
STALE_RUNNING_CONTAINER_SECONDS=14400
STALE_EXITED_CONTAINER_SECONDS=3600

# Seconds since a docker timestamp, or nothing at all when it cannot be read.
container_age_seconds() {
    node -e '
const at = new Date(process.argv[1]);
if (Number.isNaN(at.getTime())) process.exit(0);
console.log(Math.floor((Date.now() - at.getTime()) / 1000));
' "$1" 2>/dev/null || true
}

SWEPT=""
for prefix in sway-verify- sway-rspec-; do
    stale="$(docker ps -aq \
        --filter "name=^${prefix}" \
        --filter "status=exited" \
        --filter "status=dead" 2>/dev/null || true)"
    for id in $stale; do
        finished_at="$(docker inspect --format '{{.State.FinishedAt}}' "$id" 2>/dev/null || true)"
        [ -z "$finished_at" ] && continue
        age_seconds="$(container_age_seconds "$finished_at")"
        if [ -n "$age_seconds" ] && [ "$age_seconds" -gt "$STALE_EXITED_CONTAINER_SECONDS" ]; then
            docker rm -f "$id" >/dev/null 2>&1 || true
            SWEPT="$SWEPT $id"
        fi
    done

    running="$(docker ps -q --filter "name=^${prefix}" 2>/dev/null || true)"
    for id in $running; do
        started_at="$(docker inspect --format '{{.State.StartedAt}}' "$id" 2>/dev/null || true)"
        [ -z "$started_at" ] && continue
        age_seconds="$(container_age_seconds "$started_at")"
        if [ -n "$age_seconds" ] && [ "$age_seconds" -gt "$STALE_RUNNING_CONTAINER_SECONDS" ]; then
            docker rm -f "$id" >/dev/null 2>&1 || true
            SWEPT="$SWEPT $id"
        fi
    done
done
if [ -n "$SWEPT" ]; then
    echo "verify.sh: swept stale containers:$SWEPT" >&2
fi

# Abandoned per-run build directories. They live inside the vite_test
# named volume and are reachable only from a container. 1440 minutes is one
# day, longer than any run observed here, so a live run's own directory is
# never touched. public/vite* is already gitignored, so these never show up
# in git status even while they accumulate.
dip compose run --rm --no-deps rspec \
    find /app/public/vite-test -maxdepth 1 -name "run-*" -type d -mmin +1440 -exec rm -rf {} + \
    >/dev/null 2>&1 || true

# This run's own logs and summary go under tmp/verify/<pid>-<epoch>, and nothing
# ever removed the last run's. Seven days rather than one: a lane log is worth
# keeping while somebody is still working out what went wrong, and it costs
# kilobytes. The name pattern is what keeps the rescued databases in
# tmp/verify/db and the fixed tmp/verify/summary.json pointer out of reach.
find tmp/verify -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*' -mtime +7 \
    -exec rm -rf {} + 2>/dev/null || true

# --- Error collector, one session for the whole run -------------------
. scripts/dip/rustrak.sh
sway_rustrak_session_key
sway_rustrak_superuser
sway_rustrak_start

# Both addresses name rustrak:8080. Chromium runs in the container too, so
# localhost there would be the container itself and every report is refused.
: "${RUSTRAK_DSN=$(sway_rustrak_container_dsn)}"
: "${VITE_RUSTRAK_DSN=$(sway_rustrak_container_dsn)}"
export RUSTRAK_DSN="${RUSTRAK_DSN:-}"
export VITE_RUSTRAK_DSN="${VITE_RUSTRAK_DSN:-}"

# --- Per-run frontend build directory ----------------------------------
# Nested under public/vite-test — the vite_test named volume's mount point —
# not a sibling. A sibling such as vite-test-$RUN_ID would land on the macOS
# bind mount instead, where it is slower and accumulates inside the working
# tree.
#
# @lat: [[parallel-verification-gate#Why some lanes bypass dip compose run]]
SWAY_VITE_BUILD_DIR="vite-test/run-$RUN_ID"
export SWAY_VITE_BUILD_DIR

# @lat: [[verification-gates#Shard counts]]
SWAY_VERIFY_BROWSER_SHARDS="${SWAY_VERIFY_BROWSER_SHARDS:-2}"
SWAY_VERIFY_NONBROWSER_SHARDS="${SWAY_VERIFY_NONBROWSER_SHARDS:-4}"
for shard_setting in SWAY_VERIFY_BROWSER_SHARDS SWAY_VERIFY_NONBROWSER_SHARDS; do
    case "${!shard_setting}" in
        ''|*[!0-9]*|0*)
            echo "verify.sh: $shard_setting must be a positive integer — got '${!shard_setting}'" >&2
            exit 64
            ;;
    esac
done
BROWSER_SHARDS="$SWAY_VERIFY_BROWSER_SHARDS"
NONBROWSER_SHARDS="$SWAY_VERIFY_NONBROWSER_SHARDS"

# --- JS worker cap ------------------------------------------------------------
# @lat: [[parallel-verification-gate#Why the JS worker pools are capped]]
SWAY_VERIFY_JS_WORKERS="${SWAY_VERIFY_JS_WORKERS:-2}"
JS_WORKER_FLAG=""
if [ "$SWAY_VERIFY_JS_WORKERS" != "0" ] && [ "$SWAY_VERIFY_JS_WORKERS" != "uncapped" ]; then
    JS_WORKER_FLAG="--maxWorkers=$SWAY_VERIFY_JS_WORKERS"
fi

# @lat: [[verification-gates#Docker lanes]]
RAKE_GATES=(
    sway:lint:admin_guards
    sway:lint:org_admin_guards
    sway:lint:inertia_matchers
    sway:lint:env_reads
    sway:lint:migration_models
    sway:lint:inertia_prop_cache
    sway:lint:param_names
    sway:lint:rspec_constants
)

# --- Lane table ----------------------------------------------------------------
# Parallel arrays, index-aligned. Host lanes are declared first (rubocop
# through rbs-validate), in a fixed order, so the summary table reads
# consistently run to run; Docker lanes follow, with
# steep, a host lane, in the last slot.
# @lat: [[verification-gates#Host lanes]]
#
# Two lanes here go beyond the core gate list: mobile-oxlint and
# tessdata-parity (declared with the rest of the Docker lanes). Both are
# flagged at their own run_lane() branch. Reason for both, stated once here:
# CI already runs them (mobile-test.yml's `pnpm run lint`, rspec.yml's
# tesseract parity step), so a verify run that skipped them could still be
# followed by a red CI push on the same tree — the one property this whole
# gate exists to guarantee.
LANE_NAMES=(
    rubocop vitest tsc oxlint oxfmt
    mobile-jest mobile-tsc mobile-oxlint
    brakeman rbs-validate
    rake-gates rspec-browser rspec-nonbrowser tessdata-parity
    steep
)
# Printed as its own column in the summary table, where a reader otherwise
# cannot tell a lane that ran on this machine from one that ran in a container.
LANE_WHERE=(host host host host host host host host host host docker docker docker docker host)
# @lat: [[verification-gates#What a printed rerun does and does not reproduce]]
COMPOSE_RUN="docker compose -f .dockerdev/compose.yml -p sway run --rm --no-deps"
RSPEC_LANE_FLAGS="-e SWAY_TEST_DATABASE_DIR=/testdb -e SWAY_VITE_BUILD_DIR=\"$SWAY_VITE_BUILD_DIR\" -e SWAY_VERIFY_RUN_ID=\"$RUN_ID\""
LANE_RERUN=(
    "bin/rubocop"
    "pnpm test --coverage${JS_WORKER_FLAG:+ $JS_WORKER_FLAG}"
    "pnpm run tsc"
    "pnpm run lint:agent"
    "pnpm run fmt:check"
    "TZ=UTC pnpm --dir mobile exec jest --ci --forceExit --watchman=false --coverage${JS_WORKER_FLAG:+ $JS_WORKER_FLAG}"
    "pnpm --dir mobile run typecheck"
    "pnpm lint:mobile"
    "bundle exec brakeman --no-pager --exit-on-warn --exit-on-error"
    "XDG_CACHE_HOME=\"\$PWD/tmp/rbs-cache\" bundle exec rbs collection install && pnpm exec oxfmt --write rbs_collection.lock.yaml && bundle exec rbs -I sig -I sig-test validate"
    "$COMPOSE_RUN -e SWAY_VITE_BUILD_DIR=\"$SWAY_VITE_BUILD_DIR\" rspec scripts/dip/rake-gates.sh ${RAKE_GATES[*]}"
    "$COMPOSE_RUN $RSPEC_LANE_FLAGS -e SWAY_TEST_LANE=browser -e SWAY_REQUIRE_BROWSER=1 rspec bundle exec rake \"sway:test:lane[browser,$BROWSER_SHARDS]\""
    "$COMPOSE_RUN $RSPEC_LANE_FLAGS -e SWAY_TEST_LANE=nonbrowser rspec bundle exec rake \"sway:test:lane[nonbrowser,$NONBROWSER_SHARDS]\""
    "$COMPOSE_RUN rspec bundle exec rails docker:lint:tessdata_parity"
    "dip run steep"
)
LANE_COUNT=${#LANE_NAMES[@]}

# Named ahead of the trap so an interrupt during the build barrier (below,
# before any lane starts) is cleaned up the same way a lane container is.
BUILD_CONTAINER="sway-verify-build-$RUN_ID"
# @lat: [[verification-gates#Onboarding coverage gate]]
COVERAGE_CONTAINER="sway-verify-coverage-$RUN_ID"

LANE_CONTAINER=(
    "" "" "" "" ""
    "" "" ""
    "" ""
    "sway-verify-rake-gates-$RUN_ID" "sway-verify-rspec-browser-$RUN_ID" "sway-verify-rspec-nonbrowser-$RUN_ID" "sway-verify-tessdata-$RUN_ID"
    ""
)
LANE_LOG=(
    "$RUN_DIR/rubocop.log" "$RUN_DIR/vitest.log" "$RUN_DIR/tsc.log" "$RUN_DIR/oxlint.log" "$RUN_DIR/oxfmt.log"
    "$RUN_DIR/mobile-jest.log" "$RUN_DIR/mobile-tsc.log" "$RUN_DIR/mobile-oxlint.log"
    "$RUN_DIR/brakeman.log" "$RUN_DIR/rbs-validate.log"
    "$RUN_DIR/rake-gates.log" "$RUN_DIR/rspec-browser.log" "$RUN_DIR/rspec-nonbrowser.log" "$RUN_DIR/tessdata-parity.log"
    "$RUN_DIR/steep.log"
)
LANE_PID=()
LANE_START=()
LANE_DURATION=()
LANE_EXIT=()
LANE_OOM=()
LANE_STATE=()
LANE_EXAMPLES=()
LANE_FAILURES=()
# @lat: [[verification-gates#Docker lanes]]
LANE_CHECKS_RAN=()
LANE_CHECKS_FAILED=()

run_lane() {
    local idx="$1"
    case "${LANE_NAMES[$idx]}" in
        rubocop)
            # Full-project Standard Ruby lint. CI runs no rubocop and no
            # formatter check at all — this is the lane that stops offences
            # from accumulating in files nobody touched, which is exactly
            # what happened before this lane existed: 34 offences drifted into
            # 22 untouched files while CI stayed green throughout. Measured
            # full-project cost on a quiet machine: 1.7-8.2s across about
            # 1,000 files, so this lane hides under the multi-minute rspec
            # lanes.
            #
            # No cache root is set here on purpose, though this lane is where
            # the need for one showed up: rubocop's default cache root lives
            # under $HOME, and when that is unreadable the lane stalls and
            # reports no result. .rubocop.yml carries the answer instead, so the gate,
            # the pre-commit hook, a bare bin/rubocop and any editor all get
            # it — this lane is one caller of four, and was never the right
            # place to fix the other three.
            bin/rubocop
            ;;
        vitest)
            pnpm test --coverage $JS_WORKER_FLAG
            ;;
        tsc)
            pnpm run tsc
            ;;
        oxlint)
            pnpm run lint:agent
            ;;
        oxfmt)
            pnpm run fmt:check
            ;;
        mobile-jest)
            # --ci --forceExit match mobile-test.yml's `pnpm test:ci` exactly.
            # --watchman=false does not: it exists only because this host's
            # Watchman refuses to open its own state file (Operation not
            # permitted — the same class of restriction as bin/rubocop's
            # cache directory, see rbs-validate below) — proven blocking
            # (Rule 3), not a real test failure, and confirmed harmless
            # everywhere else: a one-shot, non-watch test run gets nothing
            # from Watchman's persistent file-watching daemon, and CI's own
            # runner never touches this path at all so it needs no such flag.
            TZ=UTC pnpm --dir mobile exec jest --ci --forceExit --watchman=false --coverage $JS_WORKER_FLAG
            ;;
        mobile-tsc)
            # The root tsc lane above excludes mobile/ (its own tsconfig,
            # its own React Native types) — this is the only lane that
            # type-checks it.
            pnpm --dir mobile run typecheck
            ;;
        mobile-oxlint)
            # Beyond the core gate list (see the comment at LANE_NAMES,
            # above): mobile-test.yml runs this exact check.
            pnpm lint:mobile
            ;;
        brakeman)
            # Flags matched to .github/workflows/brakeman.yml exactly, minus
            # --github-repo (CI-only check-run annotation bookkeeping, not
            # needed for a local pass/fail). No SWAY_ALLOW_HOST_RAILS: like
            # rubocop, brakeman parses source statically and never boots
            # Rails, so config/boot.rb's host guard never triggers.
            bundle exec brakeman --no-pager --exit-on-warn --exit-on-error
            ;;
        rbs-validate)
            # The collection install this lane used to start runs in a
            # sequential barrier instead (further down this file, but before
            # any lane exists to race it). This lane owns reporting that
            # install's failure: the barrier lets it through so the rest of
            # the gate still runs.
            if [ "${RBS_INSTALL_EXIT:-0}" != "0" ]; then
                local failed_step
                cat "$RBS_INSTALL_LOG"
                failed_step="$(cat "$RBS_INSTALL_STEP_FILE" 2>/dev/null || true)"
                if [ "$failed_step" = "reformat" ]; then
                    # "in place", not "installed": spec/scripts/dip_verify_cleanup_spec.rb
                    # fails if the words "rbs collection install" appear anywhere
                    # inside run_lane, which is how it catches the install being
                    # moved back into a lane.
                    echo "verify.sh: the rbs collection is in place, but rbs_collection.lock.yaml could not be reformatted (exit $RBS_INSTALL_EXIT) — it is on disk in rbs's own style, so the oxfmt lane will report it too" >&2
                else
                    echo "verify.sh: the rbs collection could not be installed (exit $RBS_INSTALL_EXIT)" >&2
                fi
                return "$RBS_INSTALL_EXIT"
            fi
            # @lat: [[rbs-signatures#Why this is not caught by the verification gate]]
            bundle exec rbs -I sig -I sig-test validate
            ;;
        rake-gates)
            # This lane never touches the frontend build itself; grouped here
            # with the two rspec lanes below, which DO read this run's build
            #, for one consistent invocation shape across the
            # three lanes that pass -e flags at all — tessdata-parity,
            # below, needs none and uses dip compose run instead.
            # @lat: [[verification-gates#Docker lanes]]
            # @lat: [[parallel-verification-gate#Why some lanes bypass dip compose run]]
            docker compose -f .dockerdev/compose.yml -p sway run --no-deps --name "${LANE_CONTAINER[$idx]}" \
                -e SWAY_VITE_BUILD_DIR="$SWAY_VITE_BUILD_DIR" \
                rspec scripts/dip/rake-gates.sh "${RAKE_GATES[@]}"
            ;;
        rspec-browser)
            # The browser-required flag below belongs to this lane and no
            # other one: a shard arrangement that loses its browser
            # must fail the run rather than drop its examples and still
            # report green.
            docker compose -f .dockerdev/compose.yml -p sway run --no-deps --name "${LANE_CONTAINER[$idx]}" \
                -e SWAY_TEST_DATABASE_DIR=/testdb \
                -e SWAY_VITE_BUILD_DIR="$SWAY_VITE_BUILD_DIR" \
                -e SWAY_TEST_LANE=browser \
                -e SWAY_VERIFY_RUN_ID="$RUN_ID" \
                -e SWAY_REQUIRE_BROWSER=1 \
                rspec bundle exec rake "sway:test:lane[browser,$BROWSER_SHARDS]"
            ;;
        rspec-nonbrowser)
            # SWAY_TEST_LANE reaches SimpleCov's command name (spec/rails_helper.rb):
            # both lanes' worker numbers restart at 1, so without the lane in
            # the name each lane's slice overwrites the other's in the shared
            # coverage report.
            docker compose -f .dockerdev/compose.yml -p sway run --no-deps --name "${LANE_CONTAINER[$idx]}" \
                -e SWAY_TEST_DATABASE_DIR=/testdb \
                -e SWAY_VITE_BUILD_DIR="$SWAY_VITE_BUILD_DIR" \
                -e SWAY_TEST_LANE=nonbrowser \
                -e SWAY_VERIFY_RUN_ID="$RUN_ID" \
                rspec bundle exec rake "sway:test:lane[nonbrowser,$NONBROWSER_SHARDS]"
            ;;
        tessdata-parity)
            # Beyond the core gate list (see the comment at LANE_NAMES,
            # above): rspec.yml runs this exact rake task after its own
            # rspec step. No -e flags needed — it only reads dockerfiles off
            # disk.
            # @lat: [[parallel-verification-gate#Why some lanes bypass dip compose run]]
            dip compose run --no-deps --name "${LANE_CONTAINER[$idx]}" \
                rspec bundle exec rails docker:lint:tessdata_parity
            ;;
        steep)
            # Host lane: `dip run steep` runs bin/steep at information severity, no compose service.
            # @lat: [[verification-gates#Host lanes]]
            dip run steep
            ;;
        # A `case` that matches nothing runs nothing and returns 0, so a lane
        # named in LANE_NAMES with no branch above would be classified green
        # having run no check at all. 2 is outside the {0,1} a lane may
        # document as a result, so such a lane reports did-not-complete.
        *)
            echo "verify.sh: no run_lane branch for lane ${LANE_NAMES[$idx]}" >&2
            return 2
            ;;
    esac
}

# @lat: [[verification-gates#How lane durations are measured]]
#
# `if run_lane ...; then ...; else ...; fi` is exempt from `set -e`'s
# errexit — the same idiom the build barrier above already uses. Without
# that exemption a red lane's non-zero exit would abort this wrapper before
# the timestamp line below ever ran, breaking duration tracking for every
# red lane specifically (the lanes this whole gate exists to report on
# accurately).
run_lane_wrapped() {
    local idx="$1"
    local status
    if run_lane "$idx"; then
        status=0
    else
        status=$?
    fi
    echo "$SECONDS" >"$RUN_DIR/.lane-end-$idx"
    # fd 3 is the terminal, handed down by the caller. This function's own
    # stdout and stderr ARE the lane's log file, so a line written the ordinary
    # way would land in the log and never be seen. Only the exit code is
    # reported, never a verdict: red and did-not-complete are told apart later,
    # by classify_lane, which can read the container that this cannot.
    printf '[%4ss] %-16s finished, exit %s\n' "$SECONDS" "${LANE_NAMES[$idx]}" "$status" >&3
    return "$status"
}

# Shared by the normal end-of-run summary and the build barrier's early exit
# on failure — one lane-facts.tsv-to-JSON writer, not two copies to drift.
write_summary() {
    facts_file="$1"
    exit_code="$2"
    summary_path="$RUN_DIR/summary.json"
    RUN_ID="$RUN_ID" STARTED_AT="$STARTED_AT" TOTAL_DURATION="$SECONDS" EXIT_CODE="$exit_code" \
        FACTS_FILE="$facts_file" SUMMARY_PATH="$summary_path" \
        node scripts/dip/verify-summary.mjs
    # Convenience pointer to the last run to finish. With two concurrent runs
    # this is a race — whichever finishes last wins the pointer — but both
    # runs' own per-run summary.json stay intact underneath it.
    cp "$summary_path" "tmp/verify/summary.json"
}

# --- Cleanup trap, registered before the first lane starts ------
# @lat: [[testing-the-toolchain#Cleanup has to survive an interrupt]]
#
# Bash gives an asynchronous command in a non-interactive shell an ignored
# SIGINT, so a terminal Ctrl-C reaches this script and none of its lanes.
# The parent runs cleanup and exits while its backgrounded child runs on
# to completion. Left alone that is ten host lanes
# still burning cores after the prompt comes back, one of them (rbs-validate)
# rewriting the tracked rbs_collection.lock.yaml, and a second run started
# straight afterwards racing those orphans over node_modules/.bin.
#
# A NEGATIVE pid names a process group, so each kill below reaches the lane
# and the tool the lane started. Every pid is cleared the moment its job is
# reaped, so no group that has since taken over a recycled pid is ever
# signalled.
cleanup() {
    status=$?
    trap - EXIT INT TERM
    for pid in "${INSTALL_PID:-}" "${RBS_INSTALL_PID:-}" "${BUILD_PID:-}" "${COVERAGE_PID:-}"; do
        if [ -n "$pid" ]; then
            kill -TERM "-$pid" >/dev/null 2>&1 || true
        fi
    done
    if [ -n "${BUILD_CONTAINER:-}" ]; then
        docker rm -f "$BUILD_CONTAINER" >/dev/null 2>&1 || true
    fi
    if [ -n "${COVERAGE_CONTAINER:-}" ]; then
        docker rm -f "$COVERAGE_CONTAINER" >/dev/null 2>&1 || true
    fi
    idx=0
    while [ "$idx" -lt "$LANE_COUNT" ]; do
        if [ -n "${LANE_PID[$idx]:-}" ]; then
            kill -TERM "-${LANE_PID[$idx]}" >/dev/null 2>&1 || true
        fi
        if [ -n "${LANE_CONTAINER[$idx]:-}" ]; then
            docker rm -f "${LANE_CONTAINER[$idx]}" >/dev/null 2>&1 || true
        fi
        idx=$((idx + 1))
    done
    exit "$status"
}
trap cleanup EXIT INT TERM

# Job control, so every background job below leads its own process group and
# the negative-pid kills in cleanup reach that job's children too. Each job is
# started with </dev/null as well: a background process group that reads the
# terminal is stopped by SIGTTIN, and this script would then wait on it
# forever. Without set -m the group kill
# fails outright and the child survives; with it, the child dies with the
# lane, and `wait` still returns each lane's own exit code (143 for a
# terminated one).
set -m

# --- Dependency install barrier: once, before any lane starts ----------------
# (Found running this plan's own lane table concurrently, not a pre-existing
# issue.) `pnpm run <script>` and `pnpm --dir mobile run/exec <script>` do not
# just execute the script — each invocation independently re-verifies the
# lockfile and rewrites node_modules/.bin/* (husky's prepare hook among them),
# even when nothing changed ("Already up to date"). Ten-plus host lanes all
# calling pnpm at the same moment raced to rewrite the SAME .bin/husky file:
# one lane executed it mid-write and got `sh: .../husky: Permission denied`
# (exit 126). The file's own mtime and mode were both fine afterward — this
# is a write race, not a real permission problem, and it is not specific to
# this worktree: any checkout with this same lane table and a shared
# node_modules hits it, intermittently, which is worse than reliably.
#
# Installing once, here, before any lane starts — the same shape the frontend
# build barrier below already uses — settles node_modules/.bin/* before any
# lane can read it concurrently. Confirmed empirically before wiring this in:
# two `pnpm run` calls launched together right after a barrier install
# produced zero install/husky output at all, where the same two calls without
# a prior barrier both printed the full reinstall each time.
INSTALL_LOG="$RUN_DIR/install.log"
progress "run $RUN_ID, $LANE_COUNT lanes — logs in $RUN_DIR/"
progress "barrier 1 of 3: installing dependencies (host and mobile)"
{
    pnpm install --frozen-lockfile &&
        pnpm --dir mobile install --frozen-lockfile
} >"$INSTALL_LOG" 2>&1 </dev/null &
INSTALL_PID=$!
if wait "$INSTALL_PID"; then
    INSTALL_EXIT=0
else
    INSTALL_EXIT=$?
fi
INSTALL_PID=""

if [ "$INSTALL_EXIT" != "0" ]; then
    # Nothing downstream is safe without settled node_modules — every
    # pnpm-based host lane would either race again or fail for real.
    echo "verify.sh: dependency install failed (exit $INSTALL_EXIT) — see $INSTALL_LOG" >&2
    INSTALL_FACTS_FILE="$RUN_DIR/.install-facts.tsv"
    printf 'install\tred\t%s\t%s\tfalse\t%s\t%s\t\t\n' \
        "$SECONDS" "$INSTALL_EXIT" "$INSTALL_LOG" \
        "pnpm install --frozen-lockfile && pnpm --dir mobile install --frozen-lockfile" \
        >"$INSTALL_FACTS_FILE"
    # @lat: [[verification-gates#Known traps]]
    if ! write_summary "$INSTALL_FACTS_FILE" 1; then
        echo "verify.sh: the summary could not be written — $INSTALL_LOG still holds the reason this run stopped" >&2
    fi
    exit 1
fi

# --- RBS collection install: also once, before any lane starts ---------------
# `rbs collection install` rewrites rbs_collection.lock.yaml in its own YAML
# style (single-quoted, differently indented) even when nothing it installs
# changed — confirmed by diffing byte for byte with whitespace ignored: same
# gems, same pinned revisions, only formatting differs. The oxfmt lane reads
# that same file and fails if its formatting is not the committed one, so
# running the install inside its own lane meant the two raced: on a clean tree
# the oxfmt lane could report a violation in a file nobody touched, and a
# re-run would pass. Running it here closes the window rather than narrowing
# it, and the reformat immediately after keeps a genuine new-gem entry while
# putting the file back the way the repo holds it.
#
# NOT fatal, unlike the pnpm install above: this needs a real .git and fails
# inside a worktree, and the other fourteen lanes are still worth running
# there. The rbs-validate lane below reports the failure instead, so it is
# still one red lane and never a silent skip.
#
# Which of the two steps ran last is written down, because they fail for
# unrelated reasons and want different things from the operator: a failed
# install leaves the lock file untouched, while a failed reformat leaves it on
# disk in rbs's own style, where the oxfmt lane will report it too.
RBS_INSTALL_LOG="$RUN_DIR/rbs-install.log"
RBS_INSTALL_STEP_FILE="$RUN_DIR/.rbs-install-step"
# @lat: [[verification-gates#Known traps]]
RBS_CACHE_HOME="$PWD/tmp/rbs-cache"
mkdir -p "$RBS_CACHE_HOME"
progress "barrier 2 of 3: installing the rbs collection"
{
    echo install >"$RBS_INSTALL_STEP_FILE"
    export XDG_CACHE_HOME="$RBS_CACHE_HOME"
    bundle exec rbs collection install &&
        echo reformat >"$RBS_INSTALL_STEP_FILE" &&
        pnpm exec oxfmt --write rbs_collection.lock.yaml
} >"$RBS_INSTALL_LOG" 2>&1 </dev/null &
RBS_INSTALL_PID=$!
if wait "$RBS_INSTALL_PID"; then
    RBS_INSTALL_EXIT=0
else
    RBS_INSTALL_EXIT=$?
fi
RBS_INSTALL_PID=""

# --- Build barrier: build once, before any lane starts ----------
# @lat: [[testing-the-toolchain#Cleanup has to survive an interrupt]]
BUILD_LOG="$RUN_DIR/build.log"
progress "barrier 3 of 3: building the frontend into $SWAY_VITE_BUILD_DIR"
docker compose -f .dockerdev/compose.yml -p sway run --rm --no-deps \
    --name "$BUILD_CONTAINER" -e SWAY_VITE_BUILD_DIR="$SWAY_VITE_BUILD_DIR" \
    rspec pnpm vite build --mode test \
    >"$BUILD_LOG" 2>&1 </dev/null &
BUILD_PID=$!
if wait "$BUILD_PID"; then
    BUILD_EXIT=0
else
    BUILD_EXIT=$?
fi
BUILD_PID=""

if [ "$BUILD_EXIT" != "0" ]; then
    # Nothing downstream is valid against a build that never finished — every
    # lane would read whatever the LAST successful build left in this run's
    # directory (nothing, since it is new), or worse, a partial write.
    echo "verify.sh: the frontend build failed (exit $BUILD_EXIT) — see $BUILD_LOG" >&2
    BUILD_FACTS_FILE="$RUN_DIR/.build-facts.tsv"
    # Trailing \t\t: the examples/failures columns rspec lanes fill in below --
    # empty here means null in summary.json, same as this lane's failures today.
    printf 'build\tred\t%s\t%s\tfalse\t%s\t%s\t\t\n' \
        "$SECONDS" "$BUILD_EXIT" "$BUILD_LOG" \
        "docker compose -f .dockerdev/compose.yml -p sway run --rm --no-deps -e SWAY_VITE_BUILD_DIR=\"$SWAY_VITE_BUILD_DIR\" rspec pnpm vite build --mode test" \
        >"$BUILD_FACTS_FILE"
    # @lat: [[verification-gates#Known traps]]
    if ! write_summary "$BUILD_FACTS_FILE" 1; then
        echo "verify.sh: the summary could not be written — $BUILD_LOG still holds the reason this run stopped" >&2
    fi
    exit 1
fi

# --- Classify one lane -------------------------------------
# `wait` is guarded by if/else so a non-zero lane does not abort this
# script under `set -e` — one red lane must not stop the others from
# finishing. Never fail fast, never retry: every lane runs to completion and
# reports once.
classify_lane() {
    local idx="$1"
    local docker_exit="" oom_raw="" oom=false
    local lane_examples="" lane_failures=""
    local lane_checks_ran="" lane_checks_failed=""
    local lane_end

    if wait "${LANE_PID[$idx]}"; then
        LANE_EXIT[$idx]=0
    else
        LANE_EXIT[$idx]=$?
    fi
    # Reaped: this pid can be handed to another process from here on, and
    # cleanup signals a whole process group by it.
    LANE_PID[$idx]=""
    # @lat: [[verification-gates#How lane durations are measured]]
    lane_end="$(cat "$RUN_DIR/.lane-end-$idx" 2>/dev/null || true)"
    [ -z "$lane_end" ] && lane_end=$SECONDS
    LANE_DURATION[$idx]=$((lane_end - LANE_START[idx]))

    if [ -n "${LANE_CONTAINER[$idx]:-}" ]; then
        # This is why no lane invocation in run_lane carries --rm: --rm removes
        # the container as part of the run, and these two reads then find
        # nothing (measured: "no such object"), leaving oom permanently false
        # and the branch below unreachable. cleanup removes every named lane
        # container instead, after this has read it, and the start-of-run sweep
        # removes what a SIGKILL left behind once it is old enough to belong to
        # no live run.
        docker_exit="$(docker inspect "${LANE_CONTAINER[$idx]}" --format '{{.State.ExitCode}}' 2>/dev/null || true)"
        oom_raw="$(docker inspect "${LANE_CONTAINER[$idx]}" --format '{{.State.OOMKilled}}' 2>/dev/null || true)"
        [ "$oom_raw" = "true" ] && oom=true
    fi
    LANE_OOM[$idx]="$oom"

    # An rspec lane's own pass/fail comes from its example count, not (only)
    # its exit code — every other lane has no such summary line to parse, so
    # they keep the exit-code-only contract the first two tracer lanes
    # shipped with.
    case "${LANE_NAMES[$idx]}" in
        rspec-*)
            read -r lane_examples lane_failures < <(rspec_lane_totals "${LANE_LOG[$idx]}")
            ;;
        rake-gates)
            read -r lane_checks_ran lane_checks_failed < <(rake_gates_totals "${LANE_LOG[$idx]}")
            ;;
    esac
    LANE_EXAMPLES[$idx]="$lane_examples"
    LANE_FAILURES[$idx]="$lane_failures"
    LANE_CHECKS_RAN[$idx]="$lane_checks_ran"
    LANE_CHECKS_FAILED[$idx]="$lane_checks_failed"

    local counted="$lane_examples" counted_failed="$lane_failures"
    if [ -n "$lane_checks_ran" ]; then
        counted="$lane_checks_ran"
        counted_failed="$lane_checks_failed"
    fi

    # Which exit codes this lane documents as a real result, as opposed to a
    # crash before the tool ran or a death by signal. Brakeman's own codes
    # (its lib/brakeman.rb): 3 = warnings found, 7 = errors raised, both from
    # the --exit-on-warn/--exit-on-error flags this lane runs with. Each is a
    # real finding, so the lane goes red; under the shared 0-or-1 rule they
    # read as a crash instead, and re-running produced the same "crash" every
    # time.
    local ok_codes="0 1"
    case "${LANE_NAMES[$idx]}" in
        brakeman) ok_codes="0 1 3 7" ;;
    esac

    # The three-state decision itself lives in scripts/dip/verify-lib.sh, where
    # a test can call it with fixture values. Every other check on this script
    # reads it as TEXT, and a regex still matches an if-chain whose branches
    # have been reordered into saying the opposite.
    LANE_STATE[$idx]="$(lane_state \
        "$docker_exit" "$oom" "${LANE_EXIT[$idx]}" \
        "$counted" "$counted_failed" "$ok_codes")"
}

# --- Start every lane (quiet while running) -----------------------------------
# Redirected straight to its own log file, not teed to the screen — no lane
# writer other than the lane itself touches its log.
idx=0
while [ "$idx" -lt "$LANE_COUNT" ]; do
    LANE_START[$idx]=$SECONDS
    run_lane_wrapped "$idx" 3>&2 >"${LANE_LOG[$idx]}" 2>&1 </dev/null &
    LANE_PID[$idx]=$!
    idx=$((idx + 1))
done
progress "started $LANE_COUNT lanes at once; each reports below as it ends"

# --- Join every lane, in declaration order ------------------------------------
# @lat: [[verification-gates#How lane durations are measured]]
idx=0
while [ "$idx" -lt "$LANE_COUNT" ]; do
    classify_lane "$idx"
    idx=$((idx + 1))
done

# --- Exit code: did-not-complete beats red beats green ----------------
EXIT_CODE=0
idx=0
while [ "$idx" -lt "$LANE_COUNT" ]; do
    case "${LANE_STATE[$idx]}" in
        did-not-complete) EXIT_CODE=2 ;;
        red) [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1 ;;
    esac
    idx=$((idx + 1))
done

# --- Onboarding coverage, once both rspec lanes are green ---------------------
# @lat: [[verification-gates#Onboarding coverage gate]]
COVERAGE_LOG="$RUN_DIR/onboarding-coverage.log"
COVERAGE_STATE="not checked, because an rspec lane is not green"
RSPEC_LANES_GREEN=true
idx=0
while [ "$idx" -lt "$LANE_COUNT" ]; do
    case "${LANE_NAMES[$idx]}" in
        rspec-*) [ "${LANE_STATE[$idx]}" = "green" ] || RSPEC_LANES_GREEN=false ;;
    esac
    idx=$((idx + 1))
done
if [ "$RSPEC_LANES_GREEN" = "true" ]; then
    progress "checking onboarding coverage against config/onboarding_coverage_floor.yml"
    docker compose -f .dockerdev/compose.yml -p sway run --rm --no-deps \
        --name "$COVERAGE_CONTAINER" \
        rspec bundle exec rake "sway:coverage:onboarding[${RUN_ID#*-}]" \
        >"$COVERAGE_LOG" 2>&1 </dev/null &
    COVERAGE_PID=$!
    if wait "$COVERAGE_PID"; then
        COVERAGE_STATE="green"
    else
        COVERAGE_STATE="red"
        [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1
    fi
    COVERAGE_PID=""
fi

# --- Summary -----------------------------------------------
FACTS_FILE="$RUN_DIR/.lane-facts.tsv"
: >"$FACTS_FILE"
idx=0
while [ "$idx" -lt "$LANE_COUNT" ]; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${LANE_NAMES[$idx]}" \
        "${LANE_STATE[$idx]}" \
        "${LANE_DURATION[$idx]}" \
        "${LANE_EXIT[$idx]}" \
        "${LANE_OOM[$idx]}" \
        "${LANE_LOG[$idx]}" \
        "${LANE_RERUN[$idx]}" \
        "${LANE_EXAMPLES[$idx]}" \
        "${LANE_FAILURES[$idx]}" \
        "${LANE_CHECKS_RAN[$idx]}" \
        "${LANE_CHECKS_FAILED[$idx]}" \
        >>"$FACTS_FILE"
    idx=$((idx + 1))
done

# @lat: [[verification-gates#Known traps]]
if ! write_summary "$FACTS_FILE" "$EXIT_CODE"; then
    echo "verify.sh: the summary could not be written — the table below and exit $EXIT_CODE still stand" >&2
fi

echo ""
printf '%-16s %-6s %-16s %8s\n' "LANE" "WHERE" "STATE" "SECONDS"
idx=0
while [ "$idx" -lt "$LANE_COUNT" ]; do
    printf '%-16s %-6s %-16s %8s\n' "${LANE_NAMES[$idx]}" "${LANE_WHERE[$idx]}" "${LANE_STATE[$idx]}" "${LANE_DURATION[$idx]}"
    idx=$((idx + 1))
done

echo ""
echo "onboarding coverage: $COVERAGE_STATE"
if [ -f "$COVERAGE_LOG" ]; then
    cat "$COVERAGE_LOG"
fi

REPORTED_RED=0
idx=0
while [ "$idx" -lt "$LANE_COUNT" ]; do
    if [ "${LANE_STATE[$idx]}" = "red" ] || [ "${LANE_STATE[$idx]}" = "did-not-complete" ]; then
        echo ""
        echo "${LANE_NAMES[$idx]} (${LANE_STATE[$idx]}): see ${LANE_LOG[$idx]}"
        # A red lane needs a way back in, not just a place to look. Without this
        # the command sits in summary.json only, where nobody reading a red
        # table goes.
        echo "  rerun: ${LANE_RERUN[$idx]}"
        REPORTED_RED=1
    fi
    idx=$((idx + 1))
done

# @lat: [[verification-gates#What a printed rerun does and does not reproduce]]
if [ "$REPORTED_RED" = "1" ]; then
    echo ""
    echo "run $RUN_ID built the frontend into $SWAY_VITE_BUILD_DIR, which each rerun above names."
    echo "A rerun runs outside verify.sh, so no error collector is started and RUSTRAK_DSN/VITE_RUSTRAK_DSN are unset: an example that needs the collector skips there, and a skip is not a pass."
fi

# Failing examples as file:line plus a one-line description, capped at
# 15 across the WHOLE run (not per lane) so a broken shared factory producing
# hundreds of failures cannot flood the screen — summary.json still carries
# every one of them, uncapped, read from the JSON just written so there is
# exactly one place this list is assembled.
# @lat: [[verification-gates#Known traps]]
if ! SUMMARY_PATH="$RUN_DIR/summary.json" node scripts/dip/verify-failing-examples.mjs; then
    echo "verify.sh: the failing-example list could not be read from $RUN_DIR/summary.json" >&2
fi

echo ""
echo "Summary: $RUN_DIR/summary.json"
echo "Logs:    $RUN_DIR/"

exit "$EXIT_CODE"
