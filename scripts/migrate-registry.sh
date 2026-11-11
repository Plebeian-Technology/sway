#!/usr/bin/env bash
#
# @lat: [[raspberry-pi-provisioning#Why moving the image store keeps its name]]

set -euo pipefail

# ---------------------------------------------------------------------------
# Settings. Set any of these in front of the command to use the script for a
# different pair of machines:
#
#   TARGET_HOST=<a machine> scripts/migrate-registry.sh copy
#
# @lat: [[raspberry-pi-provisioning#Why moving the image store keeps its name]]
# ---------------------------------------------------------------------------

. "$(dirname "$0")/../deploy/config/load.sh"
sway_load_config
sway_require SWAY_REGISTRY

# The store's name and port come from the one place the deploy reads them, so
# this script and config/deploy.yml cannot disagree about what to call it.
REGISTRY_HOSTNAME="${REGISTRY_HOSTNAME:-${SWAY_REGISTRY%%:*}}"
REGISTRY_PORT="${REGISTRY_PORT:-${SWAY_REGISTRY##*:}}"

# Where the images are moving FROM and TO. Both ends must be named on the
# command line; there is no sensible guess, and a wrong guess copies somebody
# else's images or writes over them.
sway_require SOURCE_HOST SOURCE_SSH_USER SOURCE_DIR TARGET_HOST TARGET_SSH_USER TARGET_PARENT
# @lat: [[raspberry-pi-provisioning#Why moving the image store keeps its name]]

REGISTRY_DIRNAME="$(basename "$SOURCE_DIR")"
TARGET_DIR="$TARGET_PARENT/$REGISTRY_DIRNAME"

# Each host may have its own SSH key, named by SOURCE_SSH_KEY and TARGET_SSH_KEY,
# rather than relying on keys already being loaded into the SSH agent, because a
# script you might not run for a year should not quietly depend on what someone
# loaded last time. If a key is not named or not there we leave it out, and ssh
# falls back to whatever it normally uses.
SOURCE_SSH_KEY="${SOURCE_SSH_KEY:-}"
TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"

source_ssh_opts=(-o ConnectTimeout=10)
target_ssh_opts=(-o ConnectTimeout=10)
[[ -n "$SOURCE_SSH_KEY" && -f "$SOURCE_SSH_KEY" ]] && source_ssh_opts+=(-i "$SOURCE_SSH_KEY")
[[ -n "$TARGET_SSH_KEY" && -f "$TARGET_SSH_KEY" ]] && target_ssh_opts+=(-i "$TARGET_SSH_KEY")

# ---------------------------------------------------------------------------

fail() { echo "migrate-registry: $1" >&2; exit 1; }
note() { echo; echo "--- $1"; }

on_source() { ssh "${source_ssh_opts[@]}" "$SOURCE_SSH_USER@$SOURCE_HOST" "$@"; }
on_target() { ssh "${target_ssh_opts[@]}" "$TARGET_SSH_USER@$TARGET_HOST" "$@"; }

catalog_at() { curl -sf --max-time 10 "http://$1:$REGISTRY_PORT/v2/_catalog" 2>/dev/null || true; }

# Says whether a machine's Docker will download from this image store over plain
# unencrypted HTTP.
#
# Docker normally insists on encrypted connections. It makes one exception without
# being asked: addresses on the machine itself, the ones starting 127. Our old Pi
# points the name at itself, so it got that exception for free and never needed
# any Docker settings file. The moment the name points at a DIFFERENT machine, the
# exception no longer applies, and downloads fail with the confusing message
# "server gave HTTP response to HTTPS client" — which blames encryption rather
# than the name change that caused it.
# Answers whether a machine will talk to the image store over plain unencrypted
# HTTP when it reaches it BY NAME.
#
# Prints one of three words and nothing else: yes / name-missing / cannot-ask.
# It used to print a sentence, and the safety check in 'switch' tested that
# sentence for a "yes" prefix — so rewording the sentence could have turned the
# check off silently. Words for the code, sentences for people (trust_wording).
trusts_registry() {
    local runner="$1" cfg
    cfg="$("$runner" "sudo docker info --format '{{json .RegistryConfig}}' 2>/dev/null" 2>/dev/null || true)"

    if [[ -z "$cfg" ]]; then
        echo "cannot-ask"
    elif [[ "$cfg" == *"\"$REGISTRY_HOSTNAME:$REGISTRY_PORT\""* ]]; then
        echo "yes"
    else
        echo "name-missing"
    fi
}

# Turns one of those three words into something worth reading on screen.
trust_wording() {
    case "$1" in
        yes)          echo "yes — $REGISTRY_HOSTNAME:$REGISTRY_PORT is allowed by name" ;;
        name-missing) echo "not by name — fine at 127.0.0.1, BREAKS pointing at another Pi" ;;
        cannot-ask)   echo "could not ask this machine — SSH failed, or docker wanted a password" ;;
        *)            echo "unknown ($1)" ;;
    esac
}

# Asks a machine what address it thinks the name has. If we cannot ask, prints the
# actual SSH error instead of just "(unreachable)". The first run of this script
# said "(unreachable)" and hid the real reason, which was a missing key — a word
# that describes the symptom is not worth printing.
remote_resolution() {
    local label="$1" runner="$2" out rc errfile
    errfile="$(mktemp)"
    printf '%-16s ' "$label"
    out="$("$runner" "getent hosts $REGISTRY_HOSTNAME | awk '{print \$1; exit}'" 2>"$errfile")" && rc=0 || rc=$?
    if [[ "$rc" -eq 0 && -n "$out" ]]; then
        echo "$out"
    else
        echo "(no answer — $(tr '\n' ' ' <"$errfile" | sed 's/  */ /g; s/ $//'))"
    fi
    rm -f "$errfile"
}

# ---------------------------------------------------------------------------
# status — what the name points at, asked from each place that matters.
#
# Four places, because they can each give a different answer, and each wrong
# answer breaks something different:
#   this workstation  -> our own checks, and Kamal checking the store is reachable
#   a local container -> the build tool, which UPLOADS the image
#   the old Pi        -> downloads the image when deploying there
#   the new Pi        -> downloads the image when deploying there
# ---------------------------------------------------------------------------
cmd_status() {
    note "hostname: $REGISTRY_HOSTNAME"

    printf '%-16s ' "mac shell:"
    getent hosts "$REGISTRY_HOSTNAME" 2>/dev/null | awk '{print $1}' \
        || dscacheutil -q host -a name "$REGISTRY_HOSTNAME" \
           | awk '/^ip_address/ {print $2; exit}'

    printf '%-16s ' "mac container:"
    if docker image inspect alpine:latest >/dev/null 2>&1; then
        docker run --rm alpine:latest getent hosts "$REGISTRY_HOSTNAME" 2>/dev/null \
            | awk '{print $1; exit}' || echo "(no answer)"
    else
        echo "(skipped: alpine:latest not present locally)"
    fi

    remote_resolution "source host:" on_source
    remote_resolution "target host:" on_target

    note "allowed to use plain HTTP? (needed by any Pi NOT pointing the name at itself)"
    printf '%-16s ' "source host:"; trust_wording "$(trusts_registry on_source)"
    printf '%-16s ' "target host:"; trust_wording "$(trusts_registry on_target)"

    note "asking each Pi by address, so the name is not involved at all"
    for ip in "$SOURCE_HOST" "$TARGET_HOST"; do
        printf '%-18s ' "$ip:$REGISTRY_PORT"
        local body
        body="$(catalog_at "$ip")"
        [[ -n "$body" ]] && echo "$body" || echo "(not serving)"
    done
}

# ---------------------------------------------------------------------------
# copy — send the whole folder across.
#
# The WHOLE folder, not just the image files inside it. The store is started by
# Docker Compose, and its compose.yml holds the container's name, which port it
# listens on, where its own settings file is, and the setting that lets images be
# deleted. Copy only the image files and all of that has to be worked out again by
# hand on the other side.
#
# The files travel through this workstation (out of one ssh, into another) rather than
# straight from Pi to Pi. Pi-to-Pi would mean giving one Pi permanent login access
# to the other, forever, to save one extra trip across the network, once.
#
# Safe to run while the old store is still being used. Image files are named after
# a fingerprint of their own contents, so a file that already exists is never
# rewritten — only new ones get added. Running this again later picks up anything
# uploaded in the meantime.
# ---------------------------------------------------------------------------
cmd_copy() {
    note "copying $SOURCE_SSH_USER@$SOURCE_HOST:$SOURCE_DIR -> $TARGET_SSH_USER@$TARGET_HOST:$TARGET_DIR"

    on_target "sudo mkdir -p '$TARGET_PARENT'" \
        || fail "could not create $TARGET_PARENT on the target"

    on_source "sudo tar -C '$(dirname "$SOURCE_DIR")' -cf - '$REGISTRY_DIRNAME'" \
        | on_target "sudo tar -C '$TARGET_PARENT' -xf -" \
        || fail "the copy failed; the source is untouched, so just re-run it"

    # compose.yml still names the folder as it was on the old Pi. Point it at
    # wherever the folder actually ended up on this one.
    note "pointing compose.yml at the new folder"
    on_target "sudo sed -i 's#$SOURCE_DIR/data#$TARGET_DIR/data#' '$TARGET_DIR/compose.yml' \
               && cat '$TARGET_DIR/compose.yml'" \
        || fail "could not rewrite $TARGET_DIR/compose.yml"

    echo
    echo "Copied. Nothing is serving from it yet — run 'verify' next."
}

# ---------------------------------------------------------------------------
# verify — check everything arrived, before anything relies on it.
# ---------------------------------------------------------------------------
cmd_verify() {
    note "comparing file inventories"

    local src tgt
    src="$(inventory on_source "$SOURCE_DIR/data")"
    tgt="$(inventory on_target "$TARGET_DIR/data")"

    local src_digest src_bytes src_files tgt_digest tgt_bytes tgt_files
    src_digest="$(echo "$src" | sed -n 1p)"
    src_bytes="$(echo "$src" | sed -n 2p)"
    src_files="$(echo "$src" | sed -n 3p)"
    tgt_digest="$(echo "$tgt" | sed -n 1p)"
    tgt_bytes="$(echo "$tgt" | sed -n 2p)"
    tgt_files="$(echo "$tgt" | sed -n 3p)"

    printf '  source  %s files  %s bytes  %s\n' "$src_files" "$src_bytes" "$src_digest"
    printf '  target  %s files  %s bytes  %s\n' "$tgt_files" "$tgt_bytes" "$tgt_digest"

    # Two empty folders match each other perfectly, so without this the checks below
    # all agree and it reports every file present when it compared nothing at all —
    # which is exactly what a wrong SOURCE_DIR looks like.
    [[ "$src_files" -gt 0 ]] \
        || fail "found no files under $SOURCE_DIR/data on the old Pi — check SOURCE_DIR, nothing was compared"

    [[ "$src_files" == "$tgt_files" ]] || fail "file counts differ — re-run 'copy'"
    [[ "$src_bytes" == "$tgt_bytes" ]] || fail "file byte totals differ — re-run 'copy'"
    [[ "$src_digest" == "$tgt_digest" ]] || fail "path/size inventories differ — re-run 'copy'"

    echo
    echo "Every file is present at the same path and the same size. Run 'boot' next."
}

# Builds a short fingerprint of every file's name and size, plus the totals.
#
# The first version of this used `du` to total up the folder size, and it was
# wrong. `du` also counts the space the FOLDERS themselves take up, and that
# depends on the disk they were created on rather than on what is stored in them.
# Two disks reported an 8192-byte difference across copies where every actual file
# matched exactly, and the check told us to redo a copy that had already worked
# twice.
#
# Listing every file's name and size is both stricter and clearer about what it
# proves. It catches a file that is missing, extra, renamed, or cut short — which
# is what a failed copy actually looks like. It does not check the contents of the
# files, and does not need to: the copy travels over SSH, which already refuses
# data that arrived damaged.
inventory() {
    local runner="$1" dir="$2"
    "$runner" "sudo find '$dir' -type f -printf '%P %s\n' | LC_ALL=C sort | md5sum | cut -d' ' -f1
               sudo find '$dir' -type f -printf '%s\n' | awk '{s+=\$1} END {print s+0}'
               sudo find '$dir' -type f | wc -l"
}

# ---------------------------------------------------------------------------
# boot — start the registry on the target.
#
# This only adds. The name still points at the old Pi, so we end up with a second
# store on the network that nothing is using yet. That is on purpose: it lets
# `compare` prove the new one is right BEFORE anything starts relying on it.
# ---------------------------------------------------------------------------
cmd_boot() {
    note "starting the registry on $TARGET_HOST"

    on_target "cd '$TARGET_DIR' && sudo docker compose up -d" \
        || fail "docker compose up failed on the target"

    on_target "sudo docker ps --filter name=$REGISTRY_DIRNAME --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}'"

    echo
    echo "Running. Run 'compare' next."
}

# ---------------------------------------------------------------------------
# compare — both Pis list the same images, with the same version labels.
#
# Asks each Pi by address rather than by name, so name lookups cannot affect the
# answer and we are genuinely comparing the two stores. This is the check that
# matters most: it asks each store to list what it holds, using the same requests
# a deploy makes.
# ---------------------------------------------------------------------------
cmd_compare() {
    note "comparing catalogs"

    local src_cat tgt_cat
    src_cat="$(catalog_at "$SOURCE_HOST")"
    tgt_cat="$(catalog_at "$TARGET_HOST")"

    [[ -n "$src_cat" ]] || fail "source registry at $SOURCE_HOST:$REGISTRY_PORT is not answering"
    [[ -n "$tgt_cat" ]] || fail "target registry at $TARGET_HOST:$REGISTRY_PORT is not answering — run 'boot'"

    echo "  source  $src_cat"
    echo "  target  $tgt_cat"

    local repos
    repos="$(printf '%s' "$src_cat" | ruby -rjson -e 'puts JSON.parse($stdin.read).fetch("repositories", []).join(" ")')"
    [[ -n "$repos" ]] || fail "source registry reports no repositories at all — that cannot be right"

    local mismatched=0
    note "comparing tags per repository"
    for repo in $repos; do
        local src_tags tgt_tags
        src_tags="$(curl -sf --max-time 10 "http://$SOURCE_HOST:$REGISTRY_PORT/v2/$repo/tags/list" \
            | ruby -rjson -e 'puts (JSON.parse($stdin.read)["tags"] || []).sort.join(",")' 2>/dev/null || echo "ERROR")"
        tgt_tags="$(curl -sf --max-time 10 "http://$TARGET_HOST:$REGISTRY_PORT/v2/$repo/tags/list" \
            | ruby -rjson -e 'puts (JSON.parse($stdin.read)["tags"] || []).sort.join(",")' 2>/dev/null || echo "ERROR")"

        if [[ "$src_tags" == "$tgt_tags" ]]; then
            printf '  %-20s ok (%s tags)\n' "$repo" "$(echo "$src_tags" | tr ',' '\n' | grep -c . || true)"
        else
            printf '  %-20s MISMATCH\n' "$repo"
            printf '      source: %s\n' "$src_tags"
            printf '      target: %s\n' "$tgt_tags"
            mismatched=1
        fi
    done

    [[ "$mismatched" -eq 0 ]] || fail "tag lists differ — re-run 'copy' and 'boot'"

    echo
    echo "Both registries serve identical content. Run 'switch' when ready."
}

# ---------------------------------------------------------------------------
# Editing /etc/hosts, the file that maps names to addresses.
#
# On every machine it saves a copy first, shows exactly what changed, and asks
# before writing. The workstation's file had already picked up a broken line this way — a
# name stuck onto the end of a comment, left by something that appended without a
# newline — and an edit that changes files silently is how that goes unnoticed for
# months.
# ---------------------------------------------------------------------------

# Builds the commands that point the name at address $1.
#
# Takes the name off any line it already appears on, so running this twice cannot
# leave two lines behind that disagree with each other.
#
# IT REMOVES THE NAME, NOT THE LINE. An earlier version deleted the whole line the
# name sat on. One line in /etc/hosts can map several names to one address, and
# adding a name onto an existing line is the normal way a person does it by hand —
# so on a line reading "127.0.0.1  localhost <the store's name>" that version
# deleted localhost as well. On a workstation whose file had only that line and one other,
# it emptied the file completely.
hosts_edit_program() {
    local new_ip="$1"

    # The name is put inside a search pattern below, where a dot means "any
    # character". Escaping the dots keeps it matching only the real name.
    local name_re="${REGISTRY_HOSTNAME//./\\.}"

    cat <<EOF
set -eu
backup="/etc/hosts.bak-\$(date +%Y%m%d-%H%M%S)"
sudo cp /etc/hosts "\$backup"

# Three edits, in this order, on every line:
#
#   1. On a comment line only: drop a trailing "<address> <name>" that got stuck
#      onto the end of it. That is the mess the third step below now prevents, and
#      this repairs any file that already has it.
#   2. On every line that is NOT a comment: take just the name off, leaving any
#      other names on that line alone.
#   3. Delete a line that step 2 left holding nothing but an address, since an
#      address with no names does nothing.
sudo sed -E -i.tmp \\
    -e 's/^(#.*[^0-9.])[0-9]{1,3}(\.[0-9]{1,3}){3}[[:space:]]+$name_re[[:space:]]*\$/\1/' \\
    -e '/^[[:space:]]*#/! s/[[:space:]]+$name_re([[:space:]]|\$)/\1/g' \\
    -e '/^[[:space:]]*[0-9a-fA-F.:]+[[:space:]]*\$/d' \\
    /etc/hosts
sudo rm -f /etc/hosts.tmp

# Make sure the file ends with a line ending before adding to it. If it does not,
# the new mapping gets glued onto the end of whatever the last line is — usually a
# comment — and then the name does not resolve at all. Deploys still build and
# upload; the Pi just cannot download, and the app never starts. The workstation's own file
# was already in this state, left by something that appended without a line ending.
#
# The test reads the last byte: \$(...) strips line endings, so the result is empty
# exactly when the file already ends with one.
if [ -s /etc/hosts ] && [ -n "\$(tail -c1 /etc/hosts)" ]; then
    printf '\n' | sudo tee -a /etc/hosts >/dev/null
fi

printf '%s\t%s\n' '$new_ip' '$REGISTRY_HOSTNAME' | sudo tee -a /etc/hosts >/dev/null
echo "  backup: \$backup"
diff "\$backup" /etc/hosts || true
EOF
}

# Asks before each machine, and returns without editing if the answer is no.
#
# Why ask per machine instead of once at the start: every machine prints what it
# changed AFTER it has written. With one prompt covering all three, the first diff
# reaches the screen with the other two edits already on their way, so there is no
# point at which you can look at the result and decide to stop.
#
# $2 is how many machines have already been changed, so that stopping halfway says
# what state things are in rather than "nothing changed", which would be false.
ask_before() {
    local what="$1" already_done="$2" reply

    read -r -p "  Edit /etc/hosts on $what? [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] && return 0

    [[ "$already_done" -eq 0 ]] && fail "stopped before changing anything"

    cat >&2 <<MSG

Stopped with $already_done machine(s) already changed, so they no longer agree on
where $REGISTRY_HOSTNAME is. Deploys will misbehave until they agree again.

Two ways back:
  - restore the backup each machine printed above: sudo cp <backup> /etc/hosts
  - or re-run this command and answer y for every machine.
MSG
    exit 1
}

repoint_hosts() {
    local new_ip="$1" done_count=0

    note "pointing $REGISTRY_HOSTNAME at $new_ip on all three machines"
    echo "  This is the step that changes what things actually use."
    echo "  Each machine asks first and saves a copy of its own file before writing."

    note "this workstation"
    ask_before "this workstation" "$done_count"
    bash -c "$(hosts_edit_program "$new_ip")" || fail "could not edit /etc/hosts on this workstation"
    done_count=1

    # The old Pi has to change at the same time. If the workstation starts uploading images
    # to the new Pi while the old Pi still points the name at itself, then a deploy
    # to the old Pi looks for an image that was never uploaded there, and the
    # container fails to start. Both Pis always point at whichever store is the
    # real one.
    note "source host ($SOURCE_HOST)"
    ask_before "the old Pi ($SOURCE_HOST)" "$done_count"
    on_source "$(hosts_edit_program "$new_ip")" || fail "could not edit /etc/hosts on the source host"
    done_count=2

    # The Pi that HOLDS the store points the name at itself, using 127.0.0.1.
    # Docker allows plain unencrypted connections to the machine it is running on
    # without being told to, so pointing at itself means no Docker settings file is
    # needed there. Pointing at its own network address instead would need one.
    local target_view="$new_ip"
    [[ "$new_ip" == "$TARGET_HOST" ]] && target_view="127.0.0.1"
    [[ "$new_ip" == "$SOURCE_HOST" ]] && target_view="$SOURCE_HOST"

    note "target host ($TARGET_HOST) -> $target_view"
    ask_before "the new Pi ($TARGET_HOST)" "$done_count"
    on_target "$(hosts_edit_program "$target_view")" || fail "could not edit /etc/hosts on the target host"

    note "where the name points now"
    cmd_status
}

cmd_switch() {
    # Do not point the name at a store that is not actually answering. Skip this
    # check and the problem turns up later, mid-deploy, as a confusing upload error.
    [[ -n "$(catalog_at "$TARGET_HOST")" ]] \
        || fail "the store on $TARGET_HOST:$REGISTRY_PORT is not answering — run 'boot' and 'compare' first"

    # The old Pi is about to start reaching the store over the network instead of
    # on itself, so Docker's automatic permission for its own machine stops
    # applying. Caught here it is a two-minute fix. Missed, it shows up as a
    # confusing encryption error partway through the next deploy to that Pi.
    local source_trust
    source_trust="$(trusts_registry on_source)"

    # "Could not ask" is not the same problem as "asked, and the answer was no",
    # and printing Docker settings instructions for an SSH failure sends you to fix
    # the wrong thing. Both still stop the switch — an unanswered question about the
    # machine serving the public is not a yes.
    if [[ "$source_trust" == cannot-ask ]]; then
        cat >&2 <<EOF

Could not ask the old Pi ($SOURCE_HOST) whether it will reach the image store by
name over plain unencrypted HTTP. Nothing has been changed.

That question went unanswered, which is different from being answered no. Likely
causes, in order: SSH to that machine failed, or 'sudo docker info' there wanted a
password. Check with:

    ssh $SOURCE_HOST 'sudo docker info --format "{{json .RegistryConfig}}"'

Then run 'status' and 'switch' again.
EOF
        fail "could not check whether the old Pi keeps access to the image store"
    fi

    if [[ "$source_trust" != yes ]]; then
        cat >&2 <<EOF

The old Pi is not set up to reach $REGISTRY_HOSTNAME:$REGISTRY_PORT over plain
unencrypted HTTP. It has never needed to be: it reached the store on itself, and
Docker allows that automatically. After this switch it reaches it over the
network, and downloads would fail with "server gave HTTP response to HTTPS
client".

Fix it on the old Pi. Add this to /etc/docker/daemon.json, merging it in if that
file already exists:

    {"insecure-registries": ["$REGISTRY_HOSTNAME:$REGISTRY_PORT"]}

Then reload Docker — reload, NOT restart. Docker can pick this particular setting
up without stopping anything, so every running container is left alone:

    sudo systemctl reload docker

Run 'status' to confirm, then 'switch' again.

One way this can be a false alarm: the check looks for the exact text
"$REGISTRY_HOSTNAME:$REGISTRY_PORT". An entry covering a range of addresses
instead (something like "10.0.0.0/8") would also work but would not be found
here. Read the output of the command above and decide for yourself if you see one.
EOF
        fail "the old Pi would lose access to the image store"
    fi

    repoint_hosts "$TARGET_HOST"

    cat <<EOF

Done. The store on $SOURCE_HOST is still running and still holds every image —
leave it there until a deploy through the new one has worked.

Next: run a deploy (scripts/deploy.sh). It builds the image, uploads it to
$REGISTRY_HOSTNAME:$REGISTRY_PORT (now $TARGET_HOST), and downloads it again on
the Pi running the app. That tests both directions through the new store.

If anything goes wrong: scripts/migrate-registry.sh rollback
EOF
}

cmd_rollback() {
    [[ -n "$(catalog_at "$SOURCE_HOST")" ]] \
        || fail "the store on $SOURCE_HOST:$REGISTRY_PORT is not answering — it may have been shut down already"

    repoint_hosts "$SOURCE_HOST"
    echo
    echo "Back to normal. Everything points at the old Pi's store again."
}

# ---------------------------------------------------------------------------

# Spelled out here rather than read back out of the comment at the top of this
# file. It used to print lines 3 to 12 of itself, so adding four lines of
# explanation up there pushed 'compare', 'switch' and 'rollback' off the end of
# what it printed — and 'rollback' is the one the 'switch' output tells you to
# reach for when something has gone wrong.
usage() {
    cat <<EOF
Move our own Docker image store from one Raspberry Pi to another.

An image store, or "registry", is the place deploys upload the built app image to
and download it from. We run our own on a Pi instead of paying for a hosted one.
Run this script on your workstation; it does the work on both Pis over SSH.

    scripts/migrate-registry.sh status     # what the name points at, and who answers
    scripts/migrate-registry.sh copy       # copy the image files across
    scripts/migrate-registry.sh verify     # check every file arrived
    scripts/migrate-registry.sh boot       # start it on the new Pi
    scripts/migrate-registry.sh compare    # both Pis list the same images
    scripts/migrate-registry.sh switch     # point the name at the new Pi
    scripts/migrate-registry.sh rollback   # point the name back at the old Pi

Run them in that order. Nothing before 'switch' changes what anything uses.

    old Pi (source) : $SOURCE_HOST:$REGISTRY_PORT  $SOURCE_DIR
    new Pi (target) : $TARGET_HOST:$REGISTRY_PORT  $TARGET_DIR
    name            : $REGISTRY_HOSTNAME
EOF
}

case "${1:-}" in
    status)   cmd_status ;;
    copy)     cmd_copy ;;
    verify)   cmd_verify ;;
    boot)     cmd_boot ;;
    compare)  cmd_compare ;;
    switch)   cmd_switch ;;
    rollback) cmd_rollback ;;
    *)
        usage >&2
        exit 1
        ;;
esac
