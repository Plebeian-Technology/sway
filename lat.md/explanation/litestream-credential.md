---
lat:
  mode: explanation
---
# The Litestream credential

Litestream replicates the primary database through the provider's native client, which authenticates from a service-account key file on disk.

Getting that file onto the right machine, with the right permissions, has several sharp edges.

## Why the key has to be a file on the host

The native client reads the provider's standard credential chain: a service-account JSON file plus the variable naming it. It cannot take the JSON from an environment variable.

The Litestream image is distroless, so nothing inside the container can turn one
into the other either. The file therefore has to exist on the host before the
accessory boots. The alternative replica type that would have needed no file is
not usable against this provider, for reasons recorded beside the replication
configuration itself.

The credential never lands in the working tree: it goes from the password
manager straight down the SSH pipe to the host. Pushing it is idempotent, so
running it on every deploy also handles rotation, and it exits non-zero on any
failure so the deploy stops rather than continuing with a stale key.

## Two accounts, and they are not interchangeable

The writing account can delete objects in the backup bucket, because replicating means tidying up old segments as it goes. The reading account can only look.

The machine serving production needs the writer. A standby only ever pulls a
copy down for itself, and giving it the writer's key would mean the machine
holding the second copy could erase the first. Doubling the
number of machines that can destroy the only offsite copy buys nothing.

Naming a machine by hand without also asking for the reading key is therefore
refused. That combination is almost always a slip, and the cost of the slip is
the paragraph above.

## Why the destination is read out of the deploy configuration

The machine, the SSH identity and the path all come from `config/deploy.yml`, so the credential cannot drift from the deploy it is provisioning for.

The destination comes from the accessory's own volume mount, which makes that
one file the place to change when the accessory moves to another machine. It
also means the host override that moves the application to another machine in a
single command moves the credential with it: sending the app to a new machine
while the credential still goes to the old one leaves the replicator on the new
machine starting up healthy and copying nothing, which is hard to notice.

That file is read the way the deploy tool reads it — rendered as a template
first, then parsed as YAML. Parsing it as plain YAML works only while
every template tag in the file sits inside quotes; a bare tag for the machine's
address would come back as the tag's own characters, as though they were a
hostname. That fails loudly rather than sending the credential somewhere wrong,
but it still fails.

A practice run skips it. The script can only resolve the production machine, a
practice machine runs no replication at all, and two copies writing to the same
place in cloud storage corrupt each other's history.

## Why the key file needs no elevated privileges

The key lives under the deploy account's own home rather than under a system directory.

The deploy account has no passwordless elevation, and a non-interactive SSH
session has no terminal to prompt on, so requiring it would make the push
unrunnable from a deploy. Nothing is lost: the file is `0600` inside a `0700`
directory, and the Litestream container runs as root and reads it through the
bind mount either way. Anyone who can become the deploy account can already
deploy arbitrary containers to the host, so root-owning the file would not raise
the bar — and it keeps every machine identical, with no per-host elevation rule
and no second SSH identity.

## Why the accessory is restarted after each deploy

Deploying restarts the application containers and leaves accessories alone, so the replicator keeps running with the key and configuration it started with.

Restarting it explicitly is what picks up a rotated key or a changed replication
configuration. The gap while it restarts costs nothing, because replication
resumes from where it stopped. `scripts/deploy.sh` runs `kamal accessory reboot`
on routine deploys (`--initial-deploy` false, the default) and `kamal accessory boot`
when `--initial-deploy` is passed on a fresh machine.
