---
lat:
  mode: explanation
---
# Getting a Raspberry Pi ready to serve Sway

Kamal can deploy to a machine only once an account and a key exist for it to log in with, which is precisely what Kamal cannot create for itself. Two scripts sit underneath it: one that sets a machine up, one that says whether it is ready.

## Why the setup is written down at all

A machine accumulates setup that nobody wrote down, such as disk-table entries, mounts and container runtime configuration under other accounts, and moving Sway to another machine means rediscovering it.

Putting that setup in a script makes the next machine repeatable instead of a
second round of discovery.

The script stops where Kamal starts. It installs no application, pulls no image
and runs no deploy, and it guesses nothing: every value comes from the
environment and a missing one stops the run with all the missing names printed
at once.

## A readiness check asks about the account that does the work

Every check asks whether the account that will really do the work can do it, rather than whether the machine looks right to an administrator.

Those are different questions: a readiness check run by an administrator can
report green lines on a machine where the deploy account cannot create a single
file, because a directory above it belongs to somebody else. The check therefore needs no elevated
privileges and uses none — on a properly set-up machine the deploy account has
none at all, so a check that needed it could never run where it matters.

It reads and reports and changes nothing, and it exits non-zero when any check
fails so it can gate a deploy rather than merely inform one. Its error handling
is deliberately permissive in one direction: one failed check must not stop the
rest from running.

The wait-for-disk check asks systemd rather than the file system. It reads the
`RequiresMountsFor=` setting systemd has loaded for Docker and passes when that
names the data disk's mount point or a path under it, because systemd then waits
for every mount on the way to that path. A drop-in under any file name counts.
A drop-in not yet loaded with `daemon-reload` does not count, and neither does
any other route to the same dependency.

## Why the container's own account has to own the storage directory before the first deploy

A directory shared in from the host keeps the host's ownership, which overrides whatever the image chose, so the directory has to belong to the container's numeric account before anything starts.

A directory made by the administrator is read-only to the application. The first
deploy then fails after ten minutes of nothing, saying only that the container
never became healthy, while the real message — permission denied creating a
directory under the storage path — is buried inside a container that keeps
restarting. The mode is `755` with the right owner, deliberately not `777`:
world-writable is a separate problem rather than a shortcut worth copying.

Ordering the container runtime after a mount point is the same kind of setting
and needs no restart to take effect — it changes only the order things start in
next time. Restarting the runtime on a machine already serving Sway would bounce
every container for nothing, so the restart happens only when nothing is
running.

## Why moving the image store keeps its name

The name of the machine's own image store is written into five places, two of which use it as a key recording that plain HTTP is allowed to it.

Renaming the store would mean changing all five together. Pointing the existing
name at a different machine leaves all five correct, which is why the whole
migration is a file copy plus three one-line host-table edits — and why editing
the host table is enough even for containers, since this machine answers name
lookups through a local service that reads that file and containers ask the same
service.

Nothing about the two machines is written into the script. It moves images
between two named machines using two named logins, and all four are specific to one
network, so they are required arguments rather than defaults. Moving
the store is a rare, deliberate act; naming both ends every time is the point.

The destination is the plugged-in disk rather than the machine's memory card.
The store is measured in gigabytes and only grows, and constant writing wears
memory cards out — the same reason the container runtime's own storage was moved
off the card.

Everything before the switch step only adds things: the old machine keeps
running and keeps answering, so a failed step costs nothing but the time spent
copying. The switch is the only step that changes what anything uses, and a
single command puts it back.

The list of commands lives in one place, in the usage function, rather than
being printed out of the header comment by line number — adding a sentence up
there could silently drop commands from what the script says it
can do.

## Why the host PDF extractor runs as the container's account and restarts from a path watch

The host PDF extractor runs under the container's numeric account and watches its binary inside the deploy user's home directory so routine deploys never need administrative privileges.

Uploaded hearing PDFs live inside the host storage directory owned by numeric
account `100:101`. Running `sway-pdf-extractor.service` as `User=100` and
`Group=101` lets the service read those PDFs directly without running the HTTP
listener, `mutool`, or `tesseract` as `root`. Because Debian creates home
directories with mode `0700`, provisioning widens the deploy user's home
directory and `$home/bin` to `0755` so numeric user `100` can traverse into
`$home/bin/sway-pdf-extractor` while only the deploy account can replace the
binary.

The standalone `pdf-extractor` subcommand requires only root privileges and
`SWAY_PI_STORAGE_DIR` rather than the full disk-provisioning variable set. When
an existing Raspberry Pi does not yet have `mupdf-tools`, `tesseract-ocr`,
`tesseract-ocr-eng`, or the extractor units installed, the deploy script can
invoke that focused subcommand once over SSH through the administrative sudoers
key without re-running disk or container-runtime setup.

Once those units are installed, the unprivileged deploy account still cannot run
`systemctl restart`. Instead, `sway-pdf-extractor.path` watches `PathChanged` on
`$home/bin/sway-pdf-extractor` and activates the oneshot
`sway-pdf-extractor-restart.service` unit, so an atomic binary upload into the
deploy user's own `~/bin` directory restarts the daemon without granting `sudo`
to the deploy key. All three units set `StartLimitIntervalSec=0` and
provisioning clears failed unit state with `systemctl reset-failed` before
restarting the path watcher and daemon so repeated deploys or an initial upload
cannot trip systemd start-limit throttling.
