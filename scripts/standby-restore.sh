#!/usr/bin/env bash
#
# Keep a second, up-to-date copy of Sway's production database on the standby host.
# THIS RUNS ON THE STANDBY HOST, not on your workstation.
#
#   ./standby-restore.sh run            # fetch a copy right now
#   ./standby-restore.sh status         # when it last worked, and how long it took
#   ./standby-restore.sh check          # what it would do, and whether the run
#                                       # account can write where it must
#
# Installing it, with the values named inline and the full path given to sudo:
#
#   SWAY_STANDBY_DIR=... SWAY_STANDBY_MOUNT=... \
#   SWAY_REPLICA_URL=... SWAY_GCS_KEY=... \
#   sudo <the full path to this file> install
#
# @lat: [[standby-restore#Installing from an account that cannot sudo]]
#
# @lat: [[standby-restore#Why the standby fetches instead of the live machine sending]]

set -euo pipefail

# --------------------------------------------------------------------------
# Settings
#
# NOTHING IS BAKED IN. This script is copied onto the standby machine and left
# there, and the repository it comes from is public — so it names no address, no
# disk and no cloud account of its own.
#
# A value is looked for in this order:
#
#   1. the environment
#   2. /etc/default/sway-standby-restore, which `install` writes and which the
#      timer reads back
#   3. nothing — the run stops and names what is missing
#
# There is no fourth step on purpose. A guessed folder writes the copy to the
# memory card and fills it. A guessed cloud folder fetches something nobody
# writes to any more. Both of those report success.
# --------------------------------------------------------------------------

SERVICE_NAME="sway-standby-restore"
INSTALLED_AT="/usr/local/sbin/${SERVICE_NAME}"
UNIT_DIR="/etc/systemd/system"
DEFAULTS_FILE="/etc/default/${SERVICE_NAME}"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
fail() { printf '%s: %s\n' "$SERVICE_NAME" "$*" >&2; exit 1; }

# The full path to this file, which is the form sudo needs.
# @lat: [[standby-restore#Installing from an account that cannot sudo]]
this_file() { readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "$0"; }

# Read the defaults file, but never let it beat something already set, so a
# single run can still be pointed somewhere else without editing anything.
if [[ -r "$DEFAULTS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in "" | "#"*) continue ;; esac
        name="${line%%=*}"
        [[ "$name" == "$line" ]] && continue
        [[ -z "${!name:-}" ]] && export "$name=${line#*=}"
    done < "$DEFAULTS_FILE"
fi

# Stops with every missing name listed, rather than one per attempt.
need() {
    local name missing=()

    for name in "$@"; do
        [[ -z "${!name:-}" ]] && missing+=("$name")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0

    {
        echo
        echo "${SERVICE_NAME} does not know these values:"
        echo
        printf '  %s\n' "${missing[@]}"
        echo
        echo "They are looked for in the environment, then in ${DEFAULTS_FILE}."
        echo "Nothing is guessed."
        echo
        echo "'install' writes that file from whatever is set when you run it:"
        echo
        echo "    SWAY_STANDBY_DIR=... SWAY_STANDBY_MOUNT=... \\"
        echo "    SWAY_REPLICA_URL=... SWAY_GCS_KEY=... \\"
        echo "    sudo $(this_file) install"
        echo
        echo "Naming the values inline, and giving sudo the full path, works from"
        echo "any account that can sudo — including one that cannot read this file."
        echo
        echo "The matching values live in deploy/config/sway.env in the Sway"
        echo "repository, on the machine you deploy from."
        echo
    } >&2

    exit 1
}

# Usage text must still print for someone who has set nothing at all.
case "${1:-}" in
    run | status | check | install)
        need SWAY_STANDBY_DIR SWAY_STANDBY_MOUNT SWAY_REPLICA_URL SWAY_GCS_KEY
        ;;
esac

# @lat: [[standby-restore#Why the standby fetches instead of the live machine sending]]
STANDBY_DIR="${SWAY_STANDBY_DIR:-}"

# @lat: [[standby-restore#Why the fetch refuses to run without its disk]]
STANDBY_MOUNT="${SWAY_STANDBY_MOUNT:-}"

# The cloud copy to fetch. It has to be the folder production writes to, which
# is set in config/litestream/litestream.yml. Both now read the same value out
# of deploy/config/sway.env, so they can no longer drift apart by being edited
# separately — which is what spec/config/standby_restore_spec.rb used to guard
# by pinning the two against each other.
REPLICA_URL="${SWAY_REPLICA_URL:-}"

# The Google sign-in file. scripts/provision-litestream-key.sh puts it here;
# run that from the machine you deploy from, naming this machine, before the
# first fetch. Same path config/deploy.yml mounts on the serving machine.
GCS_KEY="${SWAY_GCS_KEY:-}"

# Pinned on purpose, same as everywhere else this program appears. 0.5.x reads
# and writes a different storage layout from 0.3.x, so a silent jump to the
# newest build could change what a restore even means. Bump deliberately.
#
# This one IS written here, unlike the values above: a version number is the
# same on everybody's machine and gives nothing away.
LITESTREAM_IMAGE="${SWAY_LITESTREAM_IMAGE:-litestream/litestream:0.5.15}"

# The account the timer runs the fetch as, which is routinely not the account
# that installs it. Every readiness answer 'check' prints is about this account.
STANDBY_USER="${SWAY_STANDBY_USER:-kamal}"

# Tables counted after every fetch. A copy that restores cleanly but holds no
# rows is not a copy of anything.
COUNTED_TABLES=(users user_votes bills)

LIVE="${STANDBY_DIR}/production.sqlite3"
SCRATCH="${STANDBY_DIR}/restore-in-progress.sqlite3"
STATUS_FILE="${STANDBY_DIR}/status.json"

# --------------------------------------------------------------------------
# Checks that must pass before anything is written
# --------------------------------------------------------------------------

require_tools() {
    command -v docker >/dev/null 2>&1 \
        || fail "docker is not installed or not on PATH"

    # The copying program ships without a shell inside it, so it cannot run the
    # database checks itself. Those need sqlite3 on the machine.
    command -v sqlite3 >/dev/null 2>&1 \
        || fail "sqlite3 is missing. Install it with: sudo apt-get install -y sqlite3"

    docker info >/dev/null 2>&1 \
        || fail "this account cannot talk to docker. Add it to the docker group: sudo usermod -aG docker $(id -un), then log out and back in"
}

require_disk() {
    mountpoint -q "$STANDBY_MOUNT" \
        || fail "$STANDBY_MOUNT is not a mounted disk. Refusing to write, because a copy written to the memory card instead would fill it and still look like a success"

    mkdir -p "$STANDBY_DIR"
    [[ -w "$STANDBY_DIR" ]] || fail "cannot write to $STANDBY_DIR"
}

require_credential() {
    [[ -r "$GCS_KEY" ]] || fail "cannot read the Google sign-in file at $GCS_KEY. Send it from your workstation with: scripts/provision-litestream-key.sh <this machine's address>"
}

# --------------------------------------------------------------------------
# Reading the copy
#
# Every database question goes through here so the read is done ONE way. The
# file is opened normally rather than read-only on purpose: this database
# records that it uses a write-ahead log, and SQLite cannot open such a file
# read-only without being allowed to create a small companion file beside it.
# Asking for read-only therefore fails with "attempt to write a readonly
# database", which reads like a damaged file and is not one. The companion files
# are deleted before the copy is put in place.
# --------------------------------------------------------------------------

ask_database() {
    sqlite3 "$1" "$2"
}

count_rows() {
    local db="$1" table="$2"
    ask_database "$db" "SELECT COUNT(*) FROM ${table};" 2>/dev/null || echo "-1"
}

drop_companion_files() {
    rm -f "$1-wal" "$1-shm"
}

previous_count() {
    # Pulled out of the last written status file. Missing file, missing key or
    # anything unparseable all give -1, which the caller reads as "no previous
    # figure to compare against" rather than as a fall.
    local table="$1"
    [[ -r "$STATUS_FILE" ]] || { echo "-1"; return; }
    sed -n "s/.*\"${table}\"[[:space:]]*:[[:space:]]*\([0-9]\{1,\}\).*/\1/p" "$STATUS_FILE" | head -n1 | grep -E '^[0-9]+$' || echo "-1"
}

# --------------------------------------------------------------------------
# run — fetch a copy, check it, then put it in place
# --------------------------------------------------------------------------

cmd_run() {
    require_tools
    require_disk
    require_credential

    step "fetching the cloud copy"
    say "from:  $REPLICA_URL"
    say "to:    $SCRATCH"

    # Into a scratch name first. A fetch that dies halfway must never replace a
    # good copy, and this is the whole reason the good copy survives a bad night.
    rm -f "$SCRATCH"
    drop_companion_files "$SCRATCH"

    local started ended elapsed
    started="$(date +%s)"

    # --user makes the fetched file belong to whoever runs this rather than to
    # root. Files inside this container are otherwise root-owned, and a
    # root-owned companion file beside a database locks its owner out of it
    # afterwards — a trap already paid for when the standby moved to new hardware.
    if ! docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "${STANDBY_DIR}:/standby" \
        -v "${GCS_KEY}:/etc/litestream/gcs-key.json:ro" \
        -e GOOGLE_APPLICATION_CREDENTIALS=/etc/litestream/gcs-key.json \
        "$LITESTREAM_IMAGE" \
        restore -o "/standby/$(basename "$SCRATCH")" "$REPLICA_URL"
    then
        rm -f "$SCRATCH"
        drop_companion_files "$SCRATCH"
        fail "the fetch failed. The previous copy at $LIVE is untouched"
    fi

    ended="$(date +%s)"
    elapsed=$((ended - started))
    say "fetched in ${elapsed}s"

    [[ -s "$SCRATCH" ]] || { rm -f "$SCRATCH"; fail "the fetch produced an empty file"; }

    step "checking what arrived"

    local integrity
    integrity="$(ask_database "$SCRATCH" "PRAGMA integrity_check;" 2>&1 | head -n1 || true)"
    say "integrity_check: ${integrity}"
    if [[ "$integrity" != "ok" ]]; then
        rm -f "$SCRATCH"; drop_companion_files "$SCRATCH"
        fail "the copy did not pass its own integrity check. The previous copy at $LIVE is untouched"
    fi

    local table n prev counts_json="" warned=0
    for table in "${COUNTED_TABLES[@]}"; do
        n="$(count_rows "$SCRATCH" "$table")"
        prev="$(previous_count "$table")"

        if [[ "$n" -lt 0 ]]; then
            rm -f "$SCRATCH"; drop_companion_files "$SCRATCH"
            fail "could not count ${table} — the copy is readable but does not hold the expected tables"
        fi
        if [[ "$n" -eq 0 ]]; then
            rm -f "$SCRATCH"; drop_companion_files "$SCRATCH"
            fail "${table} has no rows. A copy that restores cleanly but holds nothing is not a copy of anything. The previous copy at $LIVE is untouched"
        fi

        if [[ "$prev" -ge 0 && "$n" -lt "$prev" ]]; then
            # A warning, not a refusal. These counts only grow in normal use, so
            # a fall is worth a person looking at. It can also be legitimate —
            # somebody deleted rows on purpose — and refusing would then wedge
            # the timer forever with no way through but editing this file.
            say "WARNING: ${table} fell from ${prev} to ${n} since the last copy"
            warned=1
        else
            say "${table}: ${n}"
        fi

        counts_json="${counts_json}${counts_json:+, }\"${table}\": ${n}"
    done

    step "putting it in place"

    # Delete the companion files the checks above created, so what gets promoted
    # is one self-contained file.
    drop_companion_files "$SCRATCH"

    # Same disk, so this swap either happens or does not — there is no moment
    # where the copy is half replaced.
    mv -f "$SCRATCH" "$LIVE"
    drop_companion_files "$LIVE"
    chmod 640 "$LIVE"

    local size
    size="$(stat -c %s "$LIVE")"

    cat > "$STATUS_FILE" <<JSON
{
  "last_success_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "restore_seconds": ${elapsed},
  "bytes": ${size},
  "counts": { ${counts_json} },
  "counts_fell": $( [[ "$warned" -eq 1 ]] && echo true || echo false ),
  "source": "${REPLICA_URL}",
  "image": "${LITESTREAM_IMAGE}",
  "path": "${LIVE}"
}
JSON

    say "copy is at $LIVE (${size} bytes)"
    say "took ${elapsed}s — that is the real recovery time"
}

# --------------------------------------------------------------------------
# status — what happened last time
# --------------------------------------------------------------------------

cmd_status() {
    if [[ -r "$STATUS_FILE" ]]; then
        cat "$STATUS_FILE"
    else
        say "no copy has been fetched yet (nothing at $STATUS_FILE)"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        step "timer"
        systemctl list-timers "${SERVICE_NAME}.timer" --no-pager 2>/dev/null || true
    fi
}

# --------------------------------------------------------------------------
# check — say what would happen, and try one real write as the run account
#
# @lat: [[standby-restore#What check has to try, and for whom]]
# --------------------------------------------------------------------------

# Runs one command line as $STANDBY_USER. Exit 111 means the question could not
# be put to that account from here.
as_run_user() {
    if [[ "$(id -un)" == "$STANDBY_USER" ]]; then
        sh -c "$1"
    elif command -v sudo >/dev/null 2>&1 && sudo -n -u "$STANDBY_USER" true 2>/dev/null; then
        sudo -n -u "$STANDBY_USER" sh -c "$1"
    else
        return 111
    fi
}

# Prints one readiness line: label, then yes, NO, or unknown.
report_as_run_user() {
    local label="$1" command_line="$2" status=0

    as_run_user "$command_line" >/dev/null 2>&1 || status=$?

    case "$status" in
        0)   say "$(printf '%-18s' "$label")yes" ;;
        111) say "$(printf '%-18s' "$label")unknown" ;;
        *)   say "$(printf '%-18s' "$label")NO" ;;
    esac
}

# Creates a file where the fetch would create one, then removes it. When the
# folder is not there yet the parent is tried instead, because that is what the
# run's own mkdir needs.
probe_write() {
    local target
    if [[ -d "$STANDBY_DIR" ]]; then
        target="$STANDBY_DIR"
    else
        target="$(dirname "$STANDBY_DIR")"
    fi

    report_as_run_user "can write there:" ": > '${target}/.sway-write-probe.$$' && rm -f '${target}/.sway-write-probe.$$'"
}

cmd_check() {
    local me
    me="$(id -un)"

    say "would fetch:      $REPLICA_URL"
    say "using sign-in:    $GCS_KEY"
    say "with program:     $LITESTREAM_IMAGE"
    say "into folder:      $STANDBY_DIR"
    say "on disk:          $STANDBY_MOUNT"
    say "final copy at:    $LIVE"
    say "runs as:          $STANDBY_USER"

    step "readiness for $STANDBY_USER"
    if [[ "$me" != "$STANDBY_USER" ]]; then
        say "you are $me. Every line below reports on $STANDBY_USER, not on you."
        say "'unknown' means this account cannot ask $STANDBY_USER anything;"
        say "re-run it as: sudo $(this_file) check"
        say ""
    fi

    report_as_run_user "disk mounted:" "mountpoint -q '$STANDBY_MOUNT'"
    report_as_run_user "sign-in readable:" "[ -r '$GCS_KEY' ]"
    report_as_run_user "sqlite3 present:" "command -v sqlite3"
    report_as_run_user "docker usable:" "docker info"
    probe_write
}

# --------------------------------------------------------------------------
# install — copy this script into place and start the daily timer
# --------------------------------------------------------------------------

cmd_install() {
    [[ "$(id -u)" -eq 0 ]] || fail "install needs root: sudo $(this_file) install"

    local run_as="$STANDBY_USER"
    id "$run_as" >/dev/null 2>&1 || fail "there is no account called '$run_as' on this machine. Set SWAY_STANDBY_USER to the account that owns $GCS_KEY"

    # Copy itself into place — unless it IS the copy in place. Re-running
    # install from /usr/local/sbin is the normal way to put the timer back after
    # someone turns it off, and `install` refuses a file onto itself with "are
    # the same file". Under `set -e` that ends the run before the timer is
    # touched, which is the opposite of what the person asked for.
    if [[ "$(readlink -f "${BASH_SOURCE[0]}")" == "$(readlink -f "$INSTALLED_AT" 2>/dev/null || true)" ]]; then
        say "already running from $INSTALLED_AT — leaving the file as it is"
    else
        install -m 0755 "${BASH_SOURCE[0]}" "$INSTALLED_AT"
        say "installed $INSTALLED_AT"
    fi

    # The timer runs with an empty environment, so this file is the only thing
    # that tells it where anything is. It is written from whatever was set when
    # install ran. An existing file is left alone — it may have been edited by
    # hand, and overwriting that silently is how a careful change disappears.
    if [[ -e "$DEFAULTS_FILE" ]]; then
        say "$DEFAULTS_FILE already exists — leaving it alone"
    else
        cat > "$DEFAULTS_FILE" <<DEFAULTS
# Settings for ${SERVICE_NAME}, written by '$0 install'.
#
# The script itself holds no addresses, disks or account names — it comes from
# a public repository. This file is where they live on this machine. Edit here
# rather than editing the script, so replacing the script keeps the settings.
SWAY_STANDBY_DIR=${STANDBY_DIR}
SWAY_STANDBY_MOUNT=${STANDBY_MOUNT}
SWAY_REPLICA_URL=${REPLICA_URL}
SWAY_GCS_KEY=${GCS_KEY}
SWAY_LITESTREAM_IMAGE=${LITESTREAM_IMAGE}
DEFAULTS
        chmod 0644 "$DEFAULTS_FILE"
        say "wrote $DEFAULTS_FILE"
    fi

    # RequiresMountsFor is the important line. Without it, a run that starts
    # while the removable disk is absent writes the copy to the memory card,
    # reports success, and fills the card. systemd refuses to start the job at
    # all while the disk is missing.
    cat > "${UNIT_DIR}/${SERVICE_NAME}.service" <<UNIT
[Unit]
Description=Fetch a fresh copy of the Sway production database from the cloud copy
Documentation=https://github.com/Plebeian-Technology/sway/blob/HEAD/docs/litestream-restore.md
RequiresMountsFor=${STANDBY_MOUNT}
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
User=${run_as}
EnvironmentFile=-${DEFAULTS_FILE}
ExecStart=${INSTALLED_AT} run
TimeoutStartSec=1800
# This machine also runs other people's applications. Take the leftovers:
# never compete with them for the processor or the disk.
Nice=10
IOSchedulingClass=idle
UNIT

    cat > "${UNIT_DIR}/${SERVICE_NAME}.timer" <<UNIT
[Unit]
Description=Daily refresh of the Sway standby database copy

[Timer]
OnCalendar=*-*-* 04:17:00
# Spread the start over a quarter of an hour so it never lands at the same
# second as anything else scheduled on the hour.
RandomizedDelaySec=900
# If the machine was off at 04:17, fetch a copy shortly after it comes back
# rather than waiting a whole day.
Persistent=true

[Install]
WantedBy=timers.target
UNIT

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}.timer"

    say "timer enabled. Next runs:"
    systemctl list-timers "${SERVICE_NAME}.timer" --no-pager || true

    step "fetch one copy now to prove it works"
    say "  sudo -u ${run_as} ${INSTALLED_AT} run"
    say "  ${INSTALLED_AT} status"
}

# --------------------------------------------------------------------------

case "${1:-}" in
    run)     cmd_run ;;
    status)  cmd_status ;;
    check)   cmd_check ;;
    install) cmd_install ;;
    *)
        say "usage: $0 {install|run|status|check}"
        say ""
        say "  install   put this on a daily timer (needs root)"
        say "  run       fetch a copy now"
        say "  status    when the last copy arrived, and how long it took"
        say "  check     say what would happen, and try one write as the run account"
        exit 64
        ;;
esac
