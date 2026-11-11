#!/usr/bin/env bash
# @lat: [[deploy-rehearsal#What a rehearsal answers that a spec harness cannot]]
#
# Usage:
#   scripts/deploy-rehearsal.sh                 # build if needed, then rehearse
#   REHEARSAL_IMAGE=sway-rehearsal:latest scripts/deploy-rehearsal.sh
#   REHEARSAL_KEEP=1 scripts/deploy-rehearsal.sh   # keep the databases to inspect

set -euo pipefail

IMAGE="${REHEARSAL_IMAGE:-sway-rehearsal:latest}"
PRISTINE="db/production.pristine.sqlite3"
WORK="tmp/deploy-rehearsal"

# The two forms under test. Everything else about the run is identical, so a
# difference in the results can only come from how the tasks are grouped.
#
# SPLIT is what bin/docker-entrypoint does today: four processes, four boots.
# MERGED is the proposal: one process, one boot, same tasks in the same order.
FORM_SPLIT='./bin/rails db:migrate:with_data && ./bin/rails db:prepare && ./bin/rails sway:setup_queue_database && ./bin/rails db:seed'
FORM_MERGED='./bin/rails db:migrate:with_data db:prepare sway:setup_queue_database db:seed'

# HAZARD MODE (--hazard). The snapshot alone cannot answer the question this
# script was written for.
#
# Measured on the 2026-07-31 snapshot: 209 schema objects before the run and 209
# after. Nothing pending changed the schema — only three data migrations ran.
# So a plain rehearsal exercises "data changed" and never exercises "the schema
# changed underneath a process that had already looked at it", which is the only
# reason merging the four invocations could be unsafe.
#
# Hazard mode supplies the missing shape. It mounts a throwaway migration that
# adds a column to `legislators` (a table db:seed writes to) and a throwaway rake
# task that asserts the column is visible to the model. In the merged form that
# task runs in the SAME process that just migrated. If Rails hands it a schema
# picture cached before the migration, it aborts and the merge does not ship.
#
# Neither file is committed to db/migrate or lib/tasks. They are bind-mounted for
# the length of one container.
PROBE_DIR="$(pwd)/$WORK/probe"
FORM_SPLIT_HAZARD="$FORM_SPLIT"' && ./bin/rails rehearsal:probe'
FORM_MERGED_HAZARD='./bin/rails db:migrate:with_data db:prepare sway:setup_queue_database db:seed rehearsal:probe'

# Written by this script rather than kept in the repo. They must never reach
# db/migrate or lib/tasks — a probe migration that escaped into the real
# migration chain would add a junk column to production.
write_probe_files() {
    mkdir -p "$PROBE_DIR"

    cat > "$PROBE_DIR/20260802000000_add_rehearsal_probe.rb" <<'PROBE_MIGRATION'
# Throwaway. Bind-mounted for the length of one container by
# scripts/deploy-rehearsal.sh --hazard. Adds a column to a table db:seed writes
# to, so a task running later in the same process has something new to notice.
class AddRehearsalProbe < ActiveRecord::Migration[8.1]
  def change
    add_column :legislators, :rehearsal_probe, :string
  end
end
PROBE_MIGRATION

    cat > "$PROBE_DIR/rehearsal_probe.rake" <<'PROBE_TASK'
# Throwaway probe, bind-mounted alongside the migration above.
#
# THE QUESTION: when db:migrate:with_data adds a column and a later task runs in
# the SAME Rails process, does that task see the new column — or a picture of the
# schema cached before the migration ran?
#
# A stale picture is the entire risk of merging the entrypoint's four rake
# invocations into one. This asks directly rather than inferring.
namespace :rehearsal do
  task probe: :environment do
    columns = Legislator.column_names

    unless columns.include?("rehearsal_probe")
      abort "STALE SCHEMA: Legislator.column_names has no rehearsal_probe, though " \
            "the migration added it earlier in this same process. #{columns.size} columns seen."
    end

    # Reading the column name is not enough — the attribute has to work.
    Legislator.first&.update!(rehearsal_probe: "written")
    puts "PROBE OK: new column visible and writable (#{columns.size} columns)."
  end
end
PROBE_TASK
}

say() { printf '\n=== %s ===\n' "$1"; }
fail() { printf '\nREHEARSAL FAILED: %s\n' "$1" >&2; exit 1; }

[ -f "$PRISTINE" ] || fail "$PRISTINE not found. This needs a real snapshot; it proves nothing without one."

# Builds the same image config/deploy.yml ships, the same way scripts/dip/preview.sh
# does. Kept in this script so the rehearsal is one command and cannot drift from
# the thing it claims to rehearse.
#
# The build-arg list is a bash ARRAY, not a string. A string of flags survives
# bash word-splitting and is silently passed to docker as ONE argument under zsh,
# which does not word-split unquoted parameters — the build then fails with
# "requires 1 argument" and nothing explains why.
build_image() {
    [ -f config/master.key ] || fail "config/master.key is required to build the production image"

    export RAILS_MASTER_KEY="$(cat config/master.key)"
    # VITE_GOOGLE_MAPS_API_KEY lives here; the production build wants it as a secret.
    [ -f .env.development ] && set -a && . ./.env.development && set +a

    if [ -f deploy/config/load.sh ]; then
        . deploy/config/load.sh
        sway_load_config || true
    fi

    local args=()
    local name value
    for name in RAILS_ALLOWED_HOSTS SWAY_GCP_PROJECT_ID SWAY_GCS_BUCKET_ASSETS SWAY_GCS_BUCKET_DB SWAY_GCS_BUCKET_LEGISLATION SWAY_LITESTREAM_PATH; do
        value="${!name:-}"
        [ -n "$value" ] && args+=(--build-arg "$name=$value")
    done
    [ -n "${SWAY_GCS_BUCKET_ASSETS:-}" ] && args+=(--build-arg "VITE_SWAY_ASSETS_BUCKET=$SWAY_GCS_BUCKET_ASSETS")

    local sentry=(--secret id=SENTRY_AUTH_TOKEN,src=/dev/null)
    [ -n "${SENTRY_AUTH_TOKEN:-}" ] && sentry=(--secret id=SENTRY_AUTH_TOKEN,env=SENTRY_AUTH_TOKEN)

    say "building $IMAGE from docker/dockerfiles/production.alpine.dockerfile"
    DOCKER_BUILDKIT=1 docker buildx build \
        --load \
        --tag "$IMAGE" \
        --secret id=RAILS_MASTER_KEY,src=config/master.key \
        --secret id=VITE_GOOGLE_MAPS_API_KEY,env=VITE_GOOGLE_MAPS_API_KEY \
        "${sentry[@]}" \
        "${args[@]}" \
        --file docker/dockerfiles/production.alpine.dockerfile \
        . || fail "the production image did not build"
}

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    build_image
fi

# @lat: [[deploy-rehearsal#Why the frontend's own note is checked before the image ships]]
FRONTEND_CHECK=$(cat <<'FRONTEND_CHECK'
require "json"

dir = "/rails/public/vite"
note = File.join(dir, "rails-vite.json")

unless File.exist?(note)
  abort "MISSING #{note}. Rails would look for app/javascript instead, find nothing, and raise on every page."
end

meta = JSON.parse(File.read(note))
manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))

%w[application.tsx public.tsx].each do |entry|
  name = [meta["sourceDir"], meta["entrypointsDir"], entry].reject { |part| part.nil? || part.empty? }.join("/")
  entry_in_manifest = manifest[name]
  abort "The build made no file for #{name}, so every page using it would raise." unless entry_in_manifest
  puts "  ok  #{name} -> #{entry_in_manifest["file"]}"
end
FRONTEND_CHECK
)

say "frontend: both entry points resolve inside the image"
printf '%s' "$FRONTEND_CHECK" | docker run --rm -i \
    --network none \
    --entrypoint sh \
    "$IMAGE" -c 'ruby -' \
    || fail "the frontend would not load in production. Read the line above — it names the file."

rm -rf "$WORK"
mkdir -p "$WORK"

# Everything the production image asks for at boot. These are FAKE on purpose:
# the rehearsal must not be able to reach anybody's real cloud account, and
# nothing under test reads their values — config/initializers/deploy_values.rb
# checks only that they are present.
#
# RAILS_MASTER_KEY is the exception and has to be real, because the app decrypts
# credentials while it starts. It is passed from config/master.key, never
# written into this file.
rehearse() {
    # Separate statements on purpose: bash expands every argument of a builtin
    # BEFORE running it, so `local a="$1" b="$a"` leaves b empty — and with
    # `set -u` it aborts with "a: unbound variable" pointing at a line that
    # looks correct.
    local label="$1"
    local command="$2"
    local dir="$WORK/$label"

    mkdir -p "$dir"
    cp "$PRISTINE" "$dir/production.sqlite3"

    local mounts=()
    if [ -n "${HAZARD:-}" ]; then
        mounts+=(-v "$PROBE_DIR/20260802000000_add_rehearsal_probe.rb:/rails/db/migrate/20260802000000_add_rehearsal_probe.rb:ro")
        mounts+=(-v "$PROBE_DIR/rehearsal_probe.rake:/rails/lib/tasks/rehearsal_probe.rake:ro")
    fi

    say "$label"
    docker run --rm \
        --network none \
        "${mounts[@]}" \
        -v "$(pwd)/$dir:/rails/storage" \
        -e RAILS_ENV=production \
        -e RAILS_MASTER_KEY="$(cat config/master.key)" \
        -e SECRET_KEY_BASE=rehearsal-secret-key-base \
        -e SWAY_DATABASE_NAME=storage/production.sqlite3 \
        -e SWAY_QUEUE_DATABASE_NAME=storage/production_queue.sqlite3 \
        -e RAILS_ALLOWED_HOSTS=localhost \
        -e SWAY_GCP_PROJECT_ID=rehearsal-not-a-real-project \
        -e SWAY_GCS_BUCKET_ASSETS=rehearsal-not-a-real-bucket \
        -e SWAY_GCS_BUCKET_DB=rehearsal-not-a-real-bucket \
        -e SWAY_GCS_BUCKET_LEGISLATION=rehearsal-not-a-real-bucket \
        -e SWAY_LITESTREAM_PATH=rehearsal-not-a-real-path \
        -e LEGISLATION_ROOT=/rails/storage/legislation \
        -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
        --entrypoint sh \
        "$IMAGE" -c "$command" \
        || fail "$label: the command itself failed. That is the answer — this form does not work."
}

# What we compare. Schema plus the migration ledgers plus every row count: if a
# task ran against a stale picture of the schema, one of these three moves.
#
# Read with the image's own sqlite3 through Ruby, NOT the host's `sqlite3`
# binary, which is an older build (3.40.1 on the Pi) and not what the app uses.
fingerprint() {
    local label="$1"
    local dir="$WORK/$1"

    # The reader is fed on stdin rather than through -e. Nesting Ruby quoting
    # inside sh quoting inside docker args is how the first version of this
    # broke, and `bundle exec` is required — the sqlite3 gem is not on the load
    # path of a bare `ruby` in this image.
    docker run --rm -i \
        --network none \
        -v "$(pwd)/$dir:/rails/storage" \
        --entrypoint sh \
        "$IMAGE" -c 'cd /rails && bundle exec ruby -' \
        < "$WORK/fingerprint.rb" \
        > "$WORK/$label.fingerprint" 2>"$WORK/$label.fingerprint.err" \
        || { cat "$WORK/$label.fingerprint.err" >&2; fail "$label: could not read the resulting database"; }
}

cat > "$WORK/fingerprint.rb" <<'RUBY'
require "sqlite3"

db = SQLite3::Database.new("/rails/storage/production.sqlite3", readonly: true)
puts "-- sqlite #{db.execute("select sqlite_version()").flatten.first}"
puts "-- page_size #{db.execute("PRAGMA page_size").flatten.first}"

objects = db.execute(<<~SQL, ["table", "index", "sqlite_%"])
  select type, name, sql from sqlite_master
  where type in (?, ?) and name not like ? order by type, name
SQL

objects.each { |type, name, sql| puts "#{type.upcase} #{name} #{sql.to_s.gsub(/\s+/, " ")}" }

objects.select { |type, _, _| type == "table" }.each do |_, name, _|
  puts "COUNT #{name} #{db.execute(%(select count(*) from "#{name}")).flatten.first}"
end
RUBY

if [ "${1:-}" = "--hazard" ]; then
    HAZARD=1
    write_probe_files
    rehearse split "$FORM_SPLIT_HAZARD"
    rehearse merged "$FORM_MERGED_HAZARD"
else
    rehearse split "$FORM_SPLIT"
    rehearse merged "$FORM_MERGED"
fi

fingerprint split
fingerprint merged

say "comparing"
if diff -u "$WORK/split.fingerprint" "$WORK/merged.fingerprint"; then
    printf '\nIDENTICAL. Both forms produce the same schema, the same migration ledger and the same row counts.\n'
    printf 'Rows compared: %s tables.\n' "$(grep -c '^COUNT' "$WORK/split.fingerprint")"
    [ -n "${REHEARSAL_KEEP:-}" ] || rm -rf "$WORK"
    exit 0
fi

printf '\nTHE TWO FORMS DISAGREE. The merge does not ship. Databases kept under %s.\n' "$WORK" >&2
exit 1
