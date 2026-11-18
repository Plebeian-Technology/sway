---
lat:
  mode: explanation
---
# What the deploy file decides

Every fact that names the machine Sway runs on — its address, its storage path, its image registry, its cloud key file — is read in one place, so pointing the application at a different machine is a one-file change.

None of those values are written in this repository, because it is published.
They come from an ignored configuration file or from the environment, and a
missing one stops the deploy naming itself rather than guessing. Reading each
value in one place keeps a value from being missed halfway through a change of
machine.

## Why the replication config file ends in .erb

The replication accessory's configuration file carries an `.erb` extension
because the deploy tool evaluates an accessory file before copying it only when
the name ends that way.

Renaming it back to a plain YAML extension sends the machine the template tags
as literal text, and replication then tries to write to a bucket whose name is
the tag itself. Its bucket and folder are not written in the file for the same
reason nothing else here is: they name an installation's cloud account.

## Why the replication sync interval is 30 seconds

Replication sets `sync-interval` to thirty seconds instead of Litestream's one-second default, trading up to thirty seconds of recoverable history for far fewer billed bucket writes.

Every upload to the bucket is a billed write, and at the default interval
Litestream sends one for each second in which the database changed. Sway's
database changes often enough that the writes, not the stored bytes and not the
network, made up most of the cloud bill.

A crash can lose the writes since the last upload, so the exposure grows from
about a second to about thirty. The six-hourly snapshots and the daily
snapshot Litestream takes itself are unaffected, and the lag check reads
position at fifteen-minute intervals, which a thirty-second delay does not
disturb.

## The ERB in the comments is not commentary

Lines that open with a hash and then an ERB tag are live code. The deploy tool
renders the file through ERB before parsing it as YAML, so the tag runs whatever
precedes it.

The hash is there only to stop YAML-only tools — the formatter among them —
treating the rest of the file as trailing content. Deleting the hash breaks the
formatter; deleting the ERB breaks the deploy. Each deploy file is rendered
separately, so every one of them needs its own copy of the block.

## Why the same values are read twice

The cloud account, its buckets and the machine's names are read once for the
image build and once for the running container, and both readings matter.

Asset precompilation boots the application in production mode on a machine that
has no copy of the ignored configuration file, since that file is kept out of
the build context; the running container asks again on every boot. Missing the
first stops the build minutes in with a backtrace. Missing the second leaves a
container that never becomes healthy and nothing to read about why.

The environment overrides the file in both directions, so deploying onto a
different machine is a matter of naming its host and storage directory on the
command line, provided that machine is set up with the same deploy account and
key.

## Why the CPU ceilings stayed where they were

The web container is capped at two cores and the job container at one, and the
caps do not scale with the speed of the machine.

Health-check timeouts come from machine-wide saturation rather than either
container's own share, so the ceiling rarely binds. A ceiling is not a
reservation, and the fix for a worker pinning a core is more processes rather
than a higher cap — Ruby runs one thread per core in each process, so extra
cores only help when there are extra processes to use them. Two web worker processes on a two-core ceiling keep a second worker
free to answer a request or health check while one is busy, without paying the
extra resident memory of a third forked worker.

## Why application containers drop all capabilities

Application containers drop all Linux capabilities and prevent privilege escalation because Rails runs as an unprivileged user on an unprivileged port, requiring zero elevated kernel privileges to serve traffic or execute background jobs.

The production Docker image runs as the non-root `rails:rails` account (UID 100) and binds Puma to unprivileged port 3333. Because the process never binds low ports (< 1024), manipulates raw network sockets, configures network interfaces, or mounts filesystems, retaining default Docker capabilities such as `CAP_NET_RAW` or `CAP_CHOWN` provides no operational value while expanding the exploit surface.

Setting `cap-drop: ["ALL"]` strips all ambient Linux capabilities from the container runtime. Complementing this with `security-opt: ["no-new-privileges:true"]` prevents child processes executed within the container from gaining new privileges through setuid binaries or filesystem capability flags. The non-kernel accessories (`cloudflare_tunnel`, `litestream`, `beszel`, and `beszel_agent`) apply the same `cap-drop: ["ALL"]` and `security-opt: ["no-new-privileges:true"]` options because their Go binaries bind unprivileged ports or initiate outbound connections without needing elevated kernel capabilities.

This defense-in-depth posture confines application vulnerabilities strictly within the process boundary, ensuring an exploited Rails process cannot escalate privileges or manipulate container isolation mechanisms.

## Why exactly one host runs jobs

The job role names a single host, and the web container never runs jobs because
the queue plugin is left commented out in the server configuration.

A second job host with its own copy of the queue database would double-send
every text message, every digest and every legislator-cache pull request. A
variable that once suggested the web container also ran jobs was removed for
the same reason: nothing read it, and leaving it made the arrangement look like
something it was not.

## Why Solid Queue runs in async supervisor mode with single-thread OpenMP

Solid Queue executes workers in async supervisor mode and caps OpenMP concurrency to one thread, minimizing resident memory on constrained hosts and preventing CPU contention under single-core job container limits.

The production job container operates under a 1.0 CPU ceiling. In Solid Queue's default fork supervisor mode, the supervisor spawns separate OS processes for supervisor, dispatcher, worker, and scheduler roles. Each process consumes 150 to 220 megabytes of resident memory even though almost all background jobs spend their execution waiting on external I/O such as HTTP APIs. In async mode, these components run as threads inside a single Ruby process, eliminating 400 to 600 megabytes of redundant memory overhead. In addition, setting `OMP_THREAD_LIMIT` to 1 prevents Tesseract OCR's OpenMP runtime from spawning multiple worker threads that saturate the single assigned CPU core and stall concurrent job execution.

## Why the registry is plain HTTP and how accessory images are tagged

The deploy file supports a plain HTTP registry with no sign-in, which is only
safe on a network the operator trusts; the password field then resolves to an
unused placeholder because the tool requires the field.

A registry that needs credentials takes a real username and password instead.
That password signs in to this registry alone. It does not gate the public
registry, since the extra service images come from a different host. Both
Docker engines involved have to allow a plain HTTP registry separately, and
they read different configuration files — a machine can therefore look
correctly configured while the engine actually in use is not.

The tunnel image (`cloudflare/cloudflared:latest`) tracks `latest` deliberately
so accessory restarts pick up upstream security updates, whereas the replication
image (`litestream/litestream:0.5.15`) is pinned to an exact version because it
holds the only continuous copy of production data and its 0.5.x release rewrote
the storage layer from WAL to LTX.

## Why a secret read from a file is stripped

A credential read into a configuration file is trimmed of surrounding
whitespace, because the ordinary way a secret reaches the machine leaves a
trailing newline on it.

Pushing a secret from a file carries that newline through, and an agent handed
a licence key with one rejects it and stops reporting in silence: no exception,
no log line, just an absence nobody notices. The trim is therefore
load-bearing rather than tidy.

One such trim survived a sweep that was supposed to catch every credential read
because the sweep searched Ruby files, and this one is ERB inside a YAML file —
structurally invisible to the search, and left unstripped by a change that
reported all of them done. The licence key itself is never written into the
file: the file is evaluated when the agent loads, so the shipped image carries
the template rather than the secret, which matters because the whole repository
is copied into an image layer.

## Why the vault account is named in the tool environment as well

The deploy script reads the vault account it signs in as from its own ignored
environment file, and the tool environment reads the same value out of that same
file a second time.

The second read is for bare commands run by hand. [[move-to-a-new-host]] is written
around those, and they never load the deploy script's environment file, so
without it the vault sign-in has no account and the reason is not obvious from
what fails. Reading it from the ignored file rather than writing it down means no
tracked file names the account, for the same reason every other installation
value is kept out of the tree.

Absence resolves to empty rather than to a default, and the secrets file treats
empty as missing on purpose: a fresh clone stops and names the variable to set,
instead of signing in as somebody else's account or failing further along.

## Why a bucket name is a build-time setting

The bucket serving audio is not a credential — its name appears in every audio
address — so it travels as an ordinary setting rather than as a build secret.

The frontend bundler fixes it into the bundle at build time, so changing the
bucket needs a rebuild rather than a restart. A missing value stops the deploy
and names itself; nothing about it is guessed.

## Why the monitoring accessories are capped and bound to private addresses

The Beszel monitoring hub and agent run on the host alongside the web application, so their network endpoints bind strictly to private addresses and their resource footprints are hard-capped to preserve capacity for core workloads.

The hub serves a metrics dashboard and historical time-series database intended solely for node operators. Publishing port 8090 only on the host's private address and on the Tailscale mesh IP keeps the dashboard off the public internet and out of the Cloudflare tunnel. When the Tailscale address is unconfigured, blank, or identical to the primary host address, the extra publish binding is omitted so Docker never binds all interfaces or a missing interface. When `SWAY_HOST` is itself a Tailscale address, [[scripts/deploy.sh]] takes it as the mesh address without probing, so the dashboard answers only on the tailnet.

`SWAY_HOST` may be a name, such as a Tailscale machine name, because SSH resolves it. Docker publishes only on an IP address, so the deploy file publishes on `SWAY_HOST` only when it is an IP address. When it is a name, the dashboard is published on `SWAY_TAILSCALE_IP`, or on loopback when that is unset. Tailscale stays optional for an installation, and the dashboard is never published on every interface.

The collector agent exposes no host port. It queries local metrics and communicates with the hub exclusively over the internal bridge network. Its volume mounts for the Docker socket and storage directory carry read-only flags to prevent container mutation or accidental writes to application data.

Storing hub time-series records on the external SSD volume avoids continuous telemetry writes to the Raspberry Pi microSD card, preventing flash storage wear. Resource limits of a quarter CPU core and small memory budgets prevent telemetry spikes from starving web requests, background job execution, or database replication.

## Why the auditd accessory audits the app user and never blocks

The auditd accessory watches the paths an exfiltration would touch, for every user including the application's own, and uses non-blocking kernel settings so auditing can never stall the host.

The watched paths are the SQLite storage directory, the Litestream service-account keyfile, the Docker daemon socket, and the deploy account's `.kamal` and `.ssh` directories under its home, where Kamal keeps the env files that carry production secrets and the SSH keys that reach the machine. Every watch applies to all users. The web and job containers run as the `rails:rails` user, and anyone who takes over the Rails process runs as that user too, so a rule that skipped it would skip exactly the reads an intrusion makes.

The exceptions are narrow and placed before the watches as `never` rules for the application user only: the four database files (`production`, `_queue`, `_cable`, `_cache`) with their `-wal`, `-shm` and `-journal` companions, and the `legislation/` pipeline artifact folder. Those are the paths the application opens on every transaction, checkpoint and pipeline run, and its routine reads of them would flood the event queue. Anything else the application user touches in storage, and anything it touches in the keyfile, the socket, `.kamal` or `.ssh`, produces a record. A rule set is replaced as a whole on each boot, by deleting every rule carrying one of the accessory's keys before the new ones are added.

Configuring non-blocking kernel audit parameters protects host availability on the Raspberry Pi. The accessory runs in the host network and PID namespaces (top-level `network: "host"` on the accessory so Kamal overrides its default `--network kamal`, plus `pid: "host"` under `options`) because the Linux kernel rejects `NETLINK_AUDIT` sockets from non-initial network namespaces (`EPERM`). It activates kernel auditing via `auditctl -e 1` and sets `--backlog_wait_time 0` and `-f 1` (printk failure mode) rather than `-f 2` (panic mode). When audit buffers fill or the audit daemon restarts, the kernel logs messages to the printk buffer and drops excess records rather than suspending syscalls or pausing application processes. Every `auditctl` and `auditd` invocation is also fail-open (`|| true`) so an absent or unsupported kernel audit subsystem never crash-loops the container.

Resource allocations are hard-capped at 0.10 CPU cores and 32 megabytes of memory. This minimal boundary respects the Raspberry Pi processor budget shared with the Cloudflare tunnel, Litestream, and Beszel monitoring accessories without contending with Puma or Solid Queue workers. Detected events are echoed to container standard output for log aggregation and forwarded synchronously to Sentry via five-second-bounded HTTP requests inside the reader loop so event bursts cannot spawn unbounded background subshells inside the 32-megabyte ceiling.

## Why Docker logging uses the local driver with rotation caps

Docker logging in `config/deploy.yml` uses the local file logging driver capped at three 10-megabyte files to prevent unbounded disk growth and reduce filesystem write overhead on the Raspberry Pi host.

The default Docker `json-file` logging driver retains container stdout and stderr in JSON without rotation unless explicitly bounded, risking storage exhaustion on the host's root filesystem or NVMe/microSD storage. The `local` driver stores rotated logs in an internal binary format with automatic compression, reducing disk write amplification and I/O latency while keeping recent container history accessible through standard `docker logs` and Kamal commands.

## Why PDF_EXTRACTOR_URL points at the host extractor port

The deploy configuration sets `PDF_EXTRACTOR_URL` in `env.clear` to the Docker host gateway on port 8085 so web and job containers route PDF text extraction and OCR to the host `sway-pdf-extractor` service.

The production Alpine image omits MuPDF and Tesseract OCR packages to keep the container image small and avoid running CPU- and memory-heavy native extraction subprocesses inside Rails containers. Setting `PDF_EXTRACTOR_URL` to `http://host.docker.internal:8085` in `env.clear` directs [[app/services/mupdf_extractor.rb#MupdfExtractor]] and [[app/services/testimony_text_extractor.rb#TestimonyTextExtractor]] over HTTP to the host systemd daemon listening on port 8085 on every interface (see [[raspberry-pi-provisioning#Getting a Raspberry Pi ready to serve Sway#Why the host PDF extractor runs as the container's account and restarts from a path watch]]).

The web and job roles map `host.docker.internal` to Docker's `host-gateway`, the bridge address the host always owns. The URL once read `sway_host`, but that value is the address deploys log in to, which is a Tailscale mesh address once the operator reaches the machine over the tailnet. Container traffic to the extractor then depended on `tailscaled` being up on the Pi, and a mesh outage would have stopped PDF extraction in an application that never leaves the machine. The bridge address exists whenever Docker runs, so the extractor path no longer depends on how the operator reaches the host.

Before Kamal deploys the Rails containers, [[scripts/deploy.sh]] cross-compiles [[ops/pdf-extractor/main.go]] locally for `linux/arm64` and probes the serving host over SSH with `SWAY_SSH_KEY` for `tesseract`, `mutool`, the English tessdata model, the `sway-pdf-extractor` service, path, and restart units (including active path-watcher status and `StartLimitIntervalSec=0`), and `$HOME/bin`. When any prerequisite is absent or stale, [[scripts/deploy.sh]] connects as an account with sudo rights, using the admin key named by `SWAY_ADMIN_SSH_KEY`, uploads [[scripts/provision-pi.sh]] over a non-TTY SSH session, and invokes its `pdf-extractor` subcommand under `sudo` over `ssh -t` before re-running the unprivileged readiness probe. Once the host prerequisites are present, [[scripts/deploy.sh]] streams the binary over `SWAY_SSH_KEY` into `$HOME/bin/sway-pdf-extractor.tmp`, atomically renames it to `$HOME/bin/sway-pdf-extractor` so `sway-pdf-extractor.path` restarts the service without `sudo`, and polls `http://127.0.0.1:8085/up` until the daemon answers healthy (re-running sudoers provisioning and service restart once if the path unit did not bring the listener up).

