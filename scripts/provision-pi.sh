#!/usr/bin/env bash
#
# Get a brand-new Raspberry Pi ready to receive Sway deploys.
# THIS RUNS ON THE PI, as a person who can use sudo — not on the Mac.
#
#   ./provision-pi.sh report   # describe this machine, change nothing
#   ./provision-pi.sh check    # say what it would do, change nothing
#   sudo -E ./provision-pi.sh apply
#
# @lat: [[raspberry-pi-provisioning#Why the setup is written down at all]]

set -euo pipefail

SCRIPT_NAME="provision-pi"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
fail() { printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# The values this needs, and where they come from
# --------------------------------------------------------------------------
#
# They live in deploy/config/sway.env in the Sway repository, on the machine you
# deploy from. This Pi has no copy of that repository, so you pass them in.
#
# PASS THEM INLINE. `sudo -E` looks like the obvious way and it is not reliable:
# whether sudo keeps your environment depends on how sudo itself is configured,
# and when it does not, everything below simply looks unset. The inline form
# never depends on that:
#
#   sudo SWAY_PI_DEPLOY_USER=kamal SWAY_PI_DISK_UUID=... \
#        ./provision-pi.sh apply

DEPLOY_USER="${SWAY_PI_DEPLOY_USER:-kamal}"
SSH_PUBKEY="${SWAY_PI_SSH_PUBKEY:-}"      # the PUBLIC half, as text or a file path
DISK_UUID="${SWAY_PI_DISK_UUID:-}"        # blkid UUID of the data disk
MOUNT_POINT="${SWAY_PI_MOUNT:-}"          # e.g. /mnt/ssd
STORAGE_DIR="${SWAY_PI_STORAGE_DIR:-}"    # e.g. /mnt/ssd/sway/storage
REGISTRY="${SWAY_PI_REGISTRY:-}"          # e.g. registry.example.local:5000

# @lat: [[raspberry-pi-provisioning#Why the container's own account has to own the storage directory before the first deploy]]
CONTAINER_UID=100
CONTAINER_GID=101

need() {
    local name missing=()

    for name in "$@"; do
        [[ -z "${!name:-}" ]] && missing+=("$name")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0

    {
        echo
        echo "${SCRIPT_NAME} does not know these values:"
        echo
        printf '  %s\n' "${missing[@]}"
        echo
        echo "The matching values live in deploy/config/sway.env in the Sway"
        echo "repository, on the machine you deploy from. Pass them inline:"
        echo
        echo "    sudo SWAY_PI_DISK_UUID=... SWAY_PI_MOUNT=... \\"
        echo "         ./provision-pi.sh apply"
        echo
        echo "Nothing is guessed."
        echo
    } >&2
    exit 1
}

# --------------------------------------------------------------------------
# report — describe the machine, touch nothing
# --------------------------------------------------------------------------

cmd_report() {
    step "this machine"
    say "model:      $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
    say "kernel:     $(uname -srm)"
    say "cores:      $(nproc)"
    say "memory:     $(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"

    # A Pi 5 shares 600mA across everything plugged into it UNLESS the power
    # supply tells it that more is available. A spinning disk drawing more than
    # that does not fail cleanly — it browns out, and what you see afterwards is
    # a database complaining about the disk, which points at the wrong thing.
    if command -v vcgencmd >/dev/null 2>&1; then
        say "psu current: $(vcgencmd get_config usb_max_current_enable 2>/dev/null || echo unknown)"
        say "throttled:   $(vcgencmd get_throttled 2>/dev/null || echo unknown)"
        say "  (throttled=0x0 is healthy. Anything else means this machine has"
        say "   been short of power or too hot, which shows up later as I/O errors.)"
    else
        say "psu current: vcgencmd not present — cannot report power"
    fi

    step "disks"
    lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINT 2>/dev/null || true

    step "docker"
    if command -v docker >/dev/null 2>&1; then
        say "version:    $(docker --version)"
        say "data root:  $(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo 'cannot ask')"
        say "insecure:   $(docker info --format '{{json .RegistryConfig.InsecureRegistryCIDRs}}' 2>/dev/null || echo 'cannot ask')"
        # A second Docker running under an ordinary account is invisible unless
        # you look for it, and it will happily answer commands that you thought
        # went to the system one.
        if pgrep -u "#1000" dockerd >/dev/null 2>&1; then
            say "WARNING:    a second Docker is running under uid 1000 (rootless)."
            say "            Commands may reach it instead of the system one."
        fi
    else
        say "docker:     not installed"
    fi

    step "deploy account"
    if id "$DEPLOY_USER" >/dev/null 2>&1; then
        say "$DEPLOY_USER exists: $(id "$DEPLOY_USER")"
        say "can sudo:   $(sudo -ln -U "$DEPLOY_USER" >/dev/null 2>&1 && echo yes || echo 'no — expected, and fine')"
    else
        say "$DEPLOY_USER does not exist yet"
    fi

    step "pdf extractor"
    say "mutool:     $(command -v mutool 2>/dev/null || echo 'not installed')"
    say "tesseract:  $(command -v tesseract 2>/dev/null || echo 'not installed')"
    if [[ -f /usr/share/tesseract-ocr/5/tessdata/eng.traineddata ]]; then
        say "tessdata:   /usr/share/tesseract-ocr/5/tessdata/eng.traineddata"
    else
        say "tessdata:   /usr/share/tesseract-ocr/5/tessdata/eng.traineddata missing"
    fi
    if [[ -f /etc/systemd/system/sway-pdf-extractor.service ]]; then
        say "service:    /etc/systemd/system/sway-pdf-extractor.service"
    else
        say "service:    /etc/systemd/system/sway-pdf-extractor.service missing"
    fi
}

# --------------------------------------------------------------------------
# the individual pieces — each says what it would do, then does it if told to
# --------------------------------------------------------------------------

APPLY=0
did() { [[ "$APPLY" -eq 1 ]]; }
plan() { say "  ${1}"; }

ensure_deploy_user() {
    step "deploy account: $DEPLOY_USER"

    if id "$DEPLOY_USER" >/dev/null 2>&1; then
        plan "already exists — leaving it alone"
    else
        plan "create $DEPLOY_USER with no password and no sudo"
        did && useradd --create-home --shell /bin/bash "$DEPLOY_USER"
    fi

    # Deliberately NOT given sudo. Anyone who can reach this account can already
    # start any container they like, so sudo would add nothing and would widen
    # what a stolen key is worth. The cost is that this account cannot install
    # anything later — which is exactly why this script exists.
    if id -nG "$DEPLOY_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
        plan "already in the docker group"
    else
        plan "add $DEPLOY_USER to the docker group"
        did && usermod -aG docker "$DEPLOY_USER"
    fi

    [[ -n "$SSH_PUBKEY" ]] || return 0

    local key_text="$SSH_PUBKEY"
    [[ -f "$SSH_PUBKEY" ]] && key_text="$(cat "$SSH_PUBKEY")"

    case "$key_text" in
        *PRIVATE*) fail "SWAY_PI_SSH_PUBKEY holds a PRIVATE key. Give the .pub half." ;;
    esac

    local home auth
    home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
    auth="$home/.ssh/authorized_keys"

    if [[ -f "$auth" ]] && grep -qF "$key_text" "$auth"; then
        plan "sign-in key already installed"
    else
        plan "install the sign-in key at $auth"
        if did; then
            install -d -m 0700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/.ssh"
            printf '%s\n' "$key_text" >> "$auth"
            chown "$DEPLOY_USER:$DEPLOY_USER" "$auth"
            chmod 0600 "$auth"
        fi
    fi
}

ensure_mount() {
    step "data disk: $MOUNT_POINT"

    # By UUID, never by /dev/sdX. Device names are handed out in the order the
    # kernel finds things, so plugging in a second disk can silently swap them
    # and mount the wrong one somewhere important.
    #
    # And never through the desktop's removable-media helper. That mounts under
    # /media/<user> only once somebody is logged in, so a machine that reboots
    # unattended comes back with the production disk missing and the app writing
    # to the SD card instead — which is how you lose data quietly.
    if grep -q "UUID=$DISK_UUID" /etc/fstab 2>/dev/null; then
        plan "already listed in /etc/fstab"
    else
        plan "add to /etc/fstab: UUID=$DISK_UUID $MOUNT_POINT ext4 defaults,nofail 0 2"
        did && printf 'UUID=%s %s ext4 defaults,nofail 0 2\n' "$DISK_UUID" "$MOUNT_POINT" >> /etc/fstab
    fi

    if [[ -d "$MOUNT_POINT" ]]; then
        plan "$MOUNT_POINT already exists"
    else
        plan "create $MOUNT_POINT"
        did && mkdir -p "$MOUNT_POINT"
    fi

    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        plan "already mounted"
    else
        plan "mount it"
        if did; then
            mount "$MOUNT_POINT"
        fi
    fi
}

ensure_storage_owner() {
    step "storage folder: $STORAGE_DIR"

    # @lat: [[raspberry-pi-provisioning#Why the container's own account has to own the storage directory before the first deploy]]
    if [[ -d "$STORAGE_DIR" ]]; then
        plan "already exists"
    else
        plan "create $STORAGE_DIR"
        did && mkdir -p "$STORAGE_DIR"
    fi

    local owner
    owner="$(stat -c '%u:%g' "$STORAGE_DIR" 2>/dev/null || echo 'unknown')"
    if [[ "$owner" == "${CONTAINER_UID}:${CONTAINER_GID}" ]]; then
        plan "already owned by ${CONTAINER_UID}:${CONTAINER_GID}"
    else
        plan "chown to ${CONTAINER_UID}:${CONTAINER_GID} (currently $owner) and chmod 755"
        if did; then
            chown -R "${CONTAINER_UID}:${CONTAINER_GID}" "$STORAGE_DIR"
            chmod 755 "$STORAGE_DIR"
        fi
    fi
}

ensure_pdf_extractor() {
    step "pdf extractor"

    # @lat: [[raspberry-pi-provisioning#Why the host PDF extractor runs as the container's account and restarts from a path watch]]
    if command -v mutool >/dev/null 2>&1 \
        && command -v tesseract >/dev/null 2>&1 \
        && [[ -f /usr/share/tesseract-ocr/5/tessdata/eng.traineddata ]]; then
        plan "mupdf-tools, tesseract-ocr, and tesseract-ocr-eng already installed"
    else
        plan "install mupdf-tools, tesseract-ocr, and tesseract-ocr-eng"
        if did; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq \
                && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
                    mupdf-tools tesseract-ocr tesseract-ocr-eng
        fi
    fi

    local home
    home="$(getent passwd "$DEPLOY_USER" 2>/dev/null | cut -d: -f6 || true)"
    [[ -z "$home" ]] && home="/home/$DEPLOY_USER"

    plan "ensure $home and $home/bin are mode 0755 so uid ${CONTAINER_UID} can traverse to $home/bin/sway-pdf-extractor"
    if did; then
        chmod 0755 "$home"
        install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/bin"
    fi

    local service_unit=/etc/systemd/system/sway-pdf-extractor.service
    if [[ -f "$service_unit" ]]; then
        plan "update $service_unit"
    else
        plan "install $service_unit"
    fi
    if did; then
        cat > "$service_unit" <<EOF
[Unit]
Description=Sway PDF Extractor
After=network.target
RequiresMountsFor=${MOUNT_POINT:-$STORAGE_DIR}
ConditionPathExists=$home/bin/sway-pdf-extractor
StartLimitIntervalSec=0

[Service]
Type=simple
User=${CONTAINER_UID}
Group=${CONTAINER_GID}
Environment="TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata"
Environment="OMP_THREAD_LIMIT=1"
Environment="PDF_EXTRACTOR_ALLOWED_ROOT=$STORAGE_DIR"
Environment="PDF_EXTRACTOR_CONTAINER_ROOT=/rails/storage"
Environment="PDF_EXTRACTOR_PORT=8085"
Environment="PDF_EXTRACTOR_CONCURRENCY=1"
ExecStart=$home/bin/sway-pdf-extractor
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
    fi

    local path_unit=/etc/systemd/system/sway-pdf-extractor.path
    local restart_unit=/etc/systemd/system/sway-pdf-extractor-restart.service
    if [[ -f "$path_unit" && -f "$restart_unit" ]]; then
        plan "update $path_unit and $restart_unit"
    else
        plan "install $path_unit and $restart_unit"
    fi
    if did; then
        cat > "$path_unit" <<EOF
[Unit]
Description=Restart Sway PDF Extractor when binary changes
StartLimitIntervalSec=0

[Path]
PathChanged=$home/bin/sway-pdf-extractor
Unit=sway-pdf-extractor-restart.service

[Install]
WantedBy=multi-user.target
EOF
        cat > "$restart_unit" <<EOF
[Unit]
Description=Restart Sway PDF Extractor
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart sway-pdf-extractor.service
EOF
        systemctl daemon-reload
        systemctl enable sway-pdf-extractor.service sway-pdf-extractor.path
        systemctl reset-failed sway-pdf-extractor.path sway-pdf-extractor-restart.service sway-pdf-extractor.service || true
        systemctl restart sway-pdf-extractor.path
        if [[ -f "$home/bin/sway-pdf-extractor" ]]; then
            systemctl restart sway-pdf-extractor.service
        fi
    fi
}

ensure_docker() {
    step "docker"

    if command -v docker >/dev/null 2>&1; then
        plan "already installed: $(docker --version)"
    else
        plan "install docker from get.docker.com"
        did && curl -fsSL https://get.docker.com | sh
    fi

    # Keep images off the SD card. Card wear is real and an image store is the
    # heaviest writer on the machine; a worn card fails in ways that read like
    # random corruption everywhere else.
    local data_root="$MOUNT_POINT/docker"
    local conf=/etc/docker/daemon.json

    if [[ -f "$conf" ]] && grep -q "\"$data_root\"" "$conf" 2>/dev/null; then
        plan "data root already $data_root"
    else
        plan "point docker's data root at $data_root and allow the plain-HTTP image store"
        plan "  NOTE: moving the data root leaves existing images behind at the old path"
        if did; then
            install -d -m 0755 /etc/docker
            cat > "$conf" <<EOF
{
  "data-root": "$data_root",
  "insecure-registries": ["$REGISTRY"]
}
EOF
        fi
    fi

    # Docker must not start before the disk holding its data root is mounted.
    # Without this it starts, finds an empty folder, and quietly builds a second
    # empty world on the SD card underneath the mount point.
    local dropin=/etc/systemd/system/docker.service.d/10-wait-for-disk.conf
    if [[ -f "$dropin" ]]; then
        plan "already waits for $MOUNT_POINT before starting"
    else
        plan "make docker wait for $MOUNT_POINT before starting"
        if did; then
            install -d -m 0755 "$(dirname "$dropin")"
            printf '[Unit]\nRequiresMountsFor=%s\n' "$MOUNT_POINT" > "$dropin"
            systemctl daemon-reload

            # @lat: [[raspberry-pi-provisioning#Why the container's own account has to own the storage directory before the first deploy]]
            if [[ -z "$(docker ps -q 2>/dev/null)" ]]; then
                plan "no containers running — restarting docker now"
                systemctl restart docker
            else
                plan "containers are running — not restarting; takes effect next docker start"
            fi
        fi
    fi
}

# --------------------------------------------------------------------------
# check / apply
# --------------------------------------------------------------------------

run_all() {
    need SWAY_PI_DISK_UUID SWAY_PI_MOUNT SWAY_PI_STORAGE_DIR SWAY_PI_REGISTRY
    ensure_deploy_user
    ensure_mount
    ensure_storage_owner
    ensure_pdf_extractor
    ensure_docker

    step "next"
    say "  ./verify-pi.sh          # prove every one of the above actually holds"
    say "  then deploy from the Mac; Kamal takes over from here"
}

case "${1:-}" in
    report) cmd_report ;;
    check)  APPLY=0; say "nothing below is done — this only says what would happen"; run_all ;;
    apply)
        [[ "$(id -u)" -eq 0 ]] || fail "apply needs root: sudo $0 apply"
        APPLY=1
        run_all
        ;;
    pdf-extractor)
        [[ "$(id -u)" -eq 0 ]] || fail "pdf-extractor needs root: sudo $0 pdf-extractor"
        need SWAY_PI_STORAGE_DIR
        APPLY=1
        ensure_pdf_extractor
        ;;
    *)
        say "usage: $0 report | check | apply | pdf-extractor"
        say ""
        say "  report         describe this machine, change nothing"
        say "  check          say what apply would do, change nothing"
        say "  apply          do it (needs root, and the values passed inline)"
        say "  pdf-extractor  install pdf extractor packages and systemd units (needs root and SWAY_PI_STORAGE_DIR)"
        exit 1
        ;;
esac
