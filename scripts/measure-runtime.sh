#!/usr/bin/env bash
# @lat: [[deploy-rehearsal#What a runtime measurement is worth]]
#
# Usage:
#   scripts/measure-runtime.sh                       # all four variants, 5 runs each
#   MEASURE_RUNS=9 scripts/measure-runtime.sh
#   MEASURE_IMAGE=sway-rehearsal:latest scripts/measure-runtime.sh

set -euo pipefail

IMAGE="${MEASURE_IMAGE:-sway-rehearsal:latest}"
RUNS="${MEASURE_RUNS:-5}"
PRISTINE="db/production.pristine.sqlite3"
WORK="tmp/measure-runtime"

fail() { printf '\nMEASUREMENT FAILED: %s\n' "$1" >&2; exit 1; }

docker image inspect "$IMAGE" >/dev/null 2>&1 \
    || fail "image $IMAGE not found. Build it with scripts/deploy-rehearsal.sh, which builds the same production image."
[ -f "$PRISTINE" ] || fail "$PRISTINE not found. Boot touches the database, so it needs one."

rm -rf "$WORK"
mkdir -p "$WORK"
cp "$PRISTINE" "$WORK/production.sqlite3"

# The workload: one full production boot that then reports its own peak memory.
# VmHWM is the high-water mark, so it survives anything freed before the read.
cat > "$WORK/probe.rb" <<'RUBY'
peak = File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1]
puts "RSS_KB=#{peak}"
puts "YJIT=#{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}"
RUBY

# Runs one variant N times and prints "<label> <median_ms> <median_rss_kb> <yjit>".
#
# jemalloc is installed inside the container rather than baked into the image, so
# this measures the SAME image both ways. If the numbers justify it, the Dockerfile
# change is `apk add jemalloc` plus the LD_PRELOAD below — nothing else moves.
measure() {
    local label="$1"
    local preload="$2"
    local times=() rsss=() out ms rss started ended yjit_on=""

    for _ in $(seq 1 "$RUNS"); do
        started=$(date +%s%N)
        out=$(docker run --rm --network none --user root \
            -v "$(pwd)/$WORK:/rails/storage" \
            -e RAILS_ENV=production \
            -e RAILS_MASTER_KEY="$(cat config/master.key)" \
            -e SECRET_KEY_BASE=measure-secret-key-base \
            -e SWAY_DATABASE_NAME=storage/production.sqlite3 \
            -e SWAY_QUEUE_DATABASE_NAME=storage/production_queue.sqlite3 \
            -e RAILS_ALLOWED_HOSTS=localhost \
            -e SWAY_GCP_PROJECT_ID=measure-not-a-real-project \
            -e SWAY_GCS_BUCKET_ASSETS=measure-not-a-real-bucket \
            -e SWAY_GCS_BUCKET_DB=measure-not-a-real-bucket \
            -e LEGISLATION_ROOT=/rails/storage/legislation \
            -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
            ${preload:+-e LD_PRELOAD=/usr/lib/libjemalloc.so.2} \
            --entrypoint sh \
            "$MEASURE_IMAGE_BUILT" -c "cd /rails && ./bin/rails runner /rails/storage/probe.rb") \
            || fail "$label: the boot itself failed"
        ended=$(date +%s%N)

        times+=($(( (ended - started) / 1000000 )))
        rsss+=("$(printf '%s\n' "$out" | sed -n 's/^RSS_KB=//p')")
        yjit_on="$(printf '%s\n' "$out" | sed -n 's/^YJIT=//p')"
    done

    ms=$(printf '%s\n' "${times[@]}" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')
    rss=$(printf '%s\n' "${rsss[@]}" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')
    printf '%-22s %8s ms %10s KB   yjit=%s\n' "$label" "$ms" "$rss" "$yjit_on"
}

# ONE image is used for both runs, with jemalloc present but only preloaded for
# the second. Installing it at measurement time would put a package manager
# inside the timed region, which is how the first version of this script
# produced six-times-slower nonsense.
MEASURE_IMAGE_BUILT="sway-measure:jemalloc"
printf 'Preparing %s (adds jemalloc to %s; needs network for this step only)\n' "$MEASURE_IMAGE_BUILT" "$IMAGE"
printf 'FROM %s\nUSER root\nRUN apk add --no-cache jemalloc\n' "$IMAGE" \
    | docker build -q -t "$MEASURE_IMAGE_BUILT" -f - . >/dev/null \
    || fail "could not add jemalloc to $IMAGE"

docker run --rm --entrypoint sh "$MEASURE_IMAGE_BUILT" -c 'test -f /usr/lib/libjemalloc.so.2' \
    || fail "jemalloc is not in the derived image. A missing LD_PRELOAD is IGNORED by musl, so the comparison would silently measure the same thing twice."

printf '\nOne full production boot per run, median of %s, image %s\n' "$RUNS" "$MEASURE_IMAGE_BUILT"
printf 'Machine: %s. Run this on the Pi for the number that decides anything.\n' "$(uname -m)"
printf 'YJIT is ON in both rows — Rails enables it (config.load_defaults 8.1).\n\n'
printf '%-22s %11s %13s\n' "variant" "boot" "peak memory"
printf -- '---------------------------------------------------------\n'

measure "baseline (musl)"   ""
measure "jemalloc"          "1"

printf -- '---------------------------------------------------------\n'
printf 'Lower is better in both columns. Boot is a single-threaded workload and is\n'
printf 'NOT where jemalloc is expected to win — the case it exists for is three Puma\n'
printf 'workers of three threads under load. Treat a flat boot number as "no harm",\n'
printf 'not as "no benefit", and get the memory figure from a loaded container.\n\n'

rm -rf "$WORK"
