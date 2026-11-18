#!/usr/bin/env bash
#
# Prove a Pi is actually ready for Sway deploys.
# THIS RUNS ON THE PI. It reads and reports; it changes nothing, ever.
#
#   ./verify-pi.sh
#
# Exits 0 when every check passes and non-zero otherwise, so it can gate a
# deploy rather than merely inform one.
#
# @lat: [[raspberry-pi-provisioning#A readiness check asks about the account that does the work]]

set -uo pipefail   # deliberately NOT -e: one failed check must not stop the rest

SCRIPT_NAME="verify-pi"

DEPLOY_USER="${SWAY_PI_DEPLOY_USER:-kamal}"
MOUNT_POINT="${SWAY_PI_MOUNT:-}"
STORAGE_DIR="${SWAY_PI_STORAGE_DIR:-}"
REGISTRY="${SWAY_PI_REGISTRY:-}"

CONTAINER_UID=100
CONTAINER_GID=101

PASSED=0
FAILED=0
WARNED=0

pass() { printf '  ok    %s\n' "$*"; PASSED=$((PASSED + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; FAILED=$((FAILED + 1)); }
warn() { printf '  note  %s\n' "$*"; WARNED=$((WARNED + 1)); }
step() { printf '\n== %s ==\n' "$*"; }

if [[ -z "$MOUNT_POINT" || -z "$STORAGE_DIR" ]]; then
    {
        echo
        echo "${SCRIPT_NAME} does not know these values:"
        echo
        [[ -z "$MOUNT_POINT" ]] && echo "  SWAY_PI_MOUNT"
        [[ -z "$STORAGE_DIR" ]] && echo "  SWAY_PI_STORAGE_DIR"
        echo
        echo "Pass them inline:"
        echo "    SWAY_PI_MOUNT=/mnt/ssd SWAY_PI_STORAGE_DIR=/mnt/ssd/sway/storage ./verify-pi.sh"
        echo
    } >&2
    exit 1
fi

# --------------------------------------------------------------------------

step "who is running this"
say_user="$(id -un)"
printf '  running as: %s (%s)\n' "$say_user" "$(id)"
if [[ "$say_user" == "$DEPLOY_USER" ]]; then
    pass "this is the deploy account, so the answers below are the ones that matter"
else
    warn "this is NOT $DEPLOY_USER. The write checks below describe $say_user, not the account that deploys."
    warn "  re-run as: sudo -u $DEPLOY_USER $0"
fi

step "the disk"
if mountpoint -q "$MOUNT_POINT"; then
    pass "$MOUNT_POINT is mounted"
else
    bad "$MOUNT_POINT is NOT mounted — the app would write to the SD card underneath it"
fi

if grep -q "[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab 2>/dev/null; then
    if grep "[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab | grep -q 'UUID='; then
        pass "listed in /etc/fstab by UUID"
    else
        bad "listed in /etc/fstab by device name, not UUID — plugging in another disk can swap them"
    fi
    grep "[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab | grep -q nofail \
        && pass "has nofail, so a missing disk cannot block boot" \
        || warn "no nofail — a missing disk will stop this machine booting"
else
    bad "NOT in /etc/fstab. It is mounted by hand or by the desktop, and will not survive a reboot."
fi

case "$MOUNT_POINT" in
    /media/*) warn "$MOUNT_POINT lives under /media, where the desktop mounts removable disks. That only happens once somebody logs in." ;;
esac

step "the storage folder"
if [[ -d "$STORAGE_DIR" ]]; then
    pass "$STORAGE_DIR exists"

    owner="$(stat -c '%u:%g' "$STORAGE_DIR")"
    mode="$(stat -c '%a' "$STORAGE_DIR")"

    if [[ "$owner" == "${CONTAINER_UID}:${CONTAINER_GID}" ]]; then
        pass "owned by ${CONTAINER_UID}:${CONTAINER_GID}, which is the account inside the container"
    else
        bad "owned by $owner, but the app runs as ${CONTAINER_UID}:${CONTAINER_GID} — the first deploy will fail with 'permission denied'"
    fi

    if [[ "$mode" == "777" ]]; then
        bad "mode is 777 — every account on this machine can rewrite the production database"
    elif [[ "$mode" == "755" ]]; then
        pass "mode is 755"
    else
        warn "mode is $mode (755 is what provisioning sets)"
    fi

    # @lat: [[raspberry-pi-provisioning#A readiness check asks about the account that does the work]]
    owner_mode="${mode: -3:1}"   # the owner digit, whatever the mode's length
    if [[ "$owner" == "${CONTAINER_UID}:${CONTAINER_GID}" && $((owner_mode & 2)) -ne 0 ]]; then
        pass "the account inside the container can write here"
    else
        bad "the account inside the container CANNOT write here"
    fi

    # Reaching a folder needs permission to enter every folder above it. The app
    # is not the owner of any of them, so each one has to let others enter.
    parent="$(dirname "$STORAGE_DIR")"
    blocked=""
    while [[ "$parent" != "/" && "$parent" != "." ]]; do
        if [[ $(($(stat -c '%a' "$parent" 2>/dev/null || echo 0) & 1)) -eq 0 ]]; then
            blocked="$parent"
            break
        fi
        parent="$(dirname "$parent")"
    done
    if [[ -n "$blocked" ]]; then
        bad "cannot even enter $blocked ($(stat -c '%U:%G %a' "$blocked" 2>/dev/null)) — so nothing below it is reachable"
    else
        pass "every folder above it can be entered"
    fi

    # Being able to write here MYSELF is not a good sign: it means the folder is
    # looser than the app needs.
    probe="$STORAGE_DIR/.verify-pi-write-probe"
    if (umask 077 && : > "$probe") 2>/dev/null; then
        rm -f "$probe"
        warn "$say_user can also create files here, which is more access than this account needs"
    fi
else
    bad "$STORAGE_DIR does not exist"
fi

step "docker"
if command -v docker >/dev/null 2>&1; then
    pass "installed: $(docker --version)"

    if docker info >/dev/null 2>&1; then
        pass "$say_user can talk to docker without sudo"

        root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)"
        case "$root" in
            "$MOUNT_POINT"/*) pass "images live on the data disk ($root)" ;;
            *)                bad "images live at $root, which is not under $MOUNT_POINT — that is SD card wear" ;;
        esac

        if [[ -n "$REGISTRY" ]]; then
            if docker info 2>/dev/null | grep -q "$REGISTRY"; then
                pass "the image store $REGISTRY is allowed over plain HTTP"
            else
                bad "$REGISTRY is not in docker's allowed list — a pull fails with 'server gave HTTP response to HTTPS client', which blames encryption and means this"
            fi
        fi
    else
        bad "$say_user cannot talk to docker. Add it to the docker group, then log out and back in."
    fi

    if systemctl show docker -p RequiresMountsFor --value 2>/dev/null | tr ' ' '\n' | grep -qxF "$MOUNT_POINT"; then
        pass "docker waits for the disk before starting"
    else
        warn "docker does not wait for $MOUNT_POINT. After a reboot it can start first and build an empty world on the SD card."
    fi

    if pgrep -u "#1000" dockerd >/dev/null 2>&1; then
        warn "a second Docker is running under uid 1000. Commands may reach it instead of the system one."
    fi
else
    bad "docker is not installed"
fi

step "the deploy account"
if id "$DEPLOY_USER" >/dev/null 2>&1; then
    pass "$DEPLOY_USER exists"
    id -nG "$DEPLOY_USER" | tr ' ' '\n' | grep -qx docker \
        && pass "in the docker group" \
        || bad "NOT in the docker group — deploys cannot start containers"

    home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
    [[ -s "$home/.ssh/authorized_keys" ]] \
        && pass "has a sign-in key installed" \
        || bad "no sign-in key at $home/.ssh/authorized_keys — Kamal cannot log in"
else
    bad "$DEPLOY_USER does not exist"
fi

step "the pdf extractor"
if command -v mutool >/dev/null 2>&1; then
    pass "mutool is installed"
else
    bad "mutool is not installed (apt-get install mupdf-tools)"
fi

if command -v tesseract >/dev/null 2>&1; then
    pass "tesseract is installed"
else
    bad "tesseract is not installed (apt-get install tesseract-ocr)"
fi

if [[ -f /usr/share/tesseract-ocr/5/tessdata/eng.traineddata ]]; then
    pass "/usr/share/tesseract-ocr/5/tessdata/eng.traineddata exists"
else
    bad "/usr/share/tesseract-ocr/5/tessdata/eng.traineddata is missing (apt-get install tesseract-ocr-eng)"
fi

if [[ -f /etc/systemd/system/sway-pdf-extractor.service ]]; then
    pass "/etc/systemd/system/sway-pdf-extractor.service exists"
else
    bad "/etc/systemd/system/sway-pdf-extractor.service is missing"
fi

if [[ -f /etc/systemd/system/sway-pdf-extractor.path ]]; then
    pass "/etc/systemd/system/sway-pdf-extractor.path exists"
else
    bad "/etc/systemd/system/sway-pdf-extractor.path is missing"
fi

# --------------------------------------------------------------------------

step "result"
printf '  %d passed, %d failed, %d worth reading\n' "$PASSED" "$FAILED" "$WARNED"

if [[ "$FAILED" -gt 0 ]]; then
    printf '\n  NOT ready. Fix the FAIL lines above, then run this again.\n\n'
    exit 1
fi

printf '\n  Ready for a deploy.\n\n'
