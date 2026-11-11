# Sway production debugging toolkit

Host-side scripts for inspecting the host that serves production (request
latency, pipeline-run load, tunnel health). **Not part of the application** —
nothing here is loaded by Rails or shipped in the image (`ops/` is in
`.dockerignore`). Run them from your workstation. The `PI_*` variable and
script names come from the reference setup, a Raspberry Pi; they work against
any host reachable over SSH.

**Point `PI_HOST` at whichever machine is serving right now.** An idle standby
host answers every check and looks healthy, so the tools would report all-clear
for the wrong machine. The address lives in your own `ops/monitoring/.env`,
which git does not track.

**Capacity note.** A legislation pipeline run is CPU-heavy, and on a small host
it competes with web requests for the same cores. These scripts show whether
host load, the origin or the tunnel is where requests slow down.

---

## Setup

```bash
cd ops/monitoring
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python pi_watch.py
```

No example file is tracked — `.gitignore` excludes every `*.env*` path. Create
`ops/monitoring/.env` by hand and fill in the values (see Authentication below).

These are the variable names the scripts read:

`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_ZONE_ID`,
`CLOUDFLARE_TUNNEL_ID`, `CLOUDFLARED_METRICS_PORT`, `NEW_RELIC_USER_KEY`,
`NEW_RELIC_ACCOUNT_ID`, `NEW_RELIC_APP_NAME`, `ORIGIN_HOST_HEADER`,
`ORIGIN_UP_PATH`, `PI_PROXY_CONTAINER`, `PI_STORAGE_PATH`, `PI_PRIMARY_DB`,
`PI_QUEUE_DB`, `PI_CABLE_DB`.

`CLOUDFLARE_TUNNEL_ID` is optional. Leave it unset and `cf_analytics.py` prints
one line saying the tunnel check is skipped, then runs the 5xx breakdown as
usual.

(Python 3.10+. Only one dependency — `rich`. Everything else is stdlib + your
system `ssh`.)

---

## Authentication — what you need to provide

| Need | What | Where it's used | Notes |
|------|------|-----------------|-------|
| **SSH to the host** | Your existing **Kamal deploy key** and user (`SWAY_SSH_KEY` / `SWAY_DEPLOY_USER`) | `pi_watch`, `tunnel_probe`, `edge_vs_origin` | **Nothing new to mint.** That key already has docker-group access, so `docker stats/logs/inspect` work over it. Off-LAN, set `PI_HOST` to the host's Tailscale IP, if it has one. |
| **`sqlite3` on the host** | `sudo apt install sqlite3` on the host | `pi_watch` DB panels | Optional — panels show `n/a` without it; everything else still works. Reads are **read-only**, WAL-safe, and can't disturb the app. |
| **Cloudflare API token** | Scoped, **read-only**: `Account > Cloudflare Tunnel > Read` + `Zone > Analytics > Read` (your site's zone) | `cf_analytics` | Create at <https://dash.cloudflare.com/profile/api-tokens>. Also set `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_ZONE_ID` (the zone's dashboard → overview, right sidebar). For the tunnel ID, open the tunnel's page in the Cloudflare dashboard or read the connector's own startup log line, then put it in `ops/monitoring/.env` as `CLOUDFLARE_TUNNEL_ID`. |
| **New Relic** | `NEW_RELIC_USER_KEY` (`NRAK-…`) + `NEW_RELIC_ACCOUNT_ID` | `newrelic_query` | You already have these in your secret store (the same values Kamal injects; the reference setup uses Bitwarden). User keys: <https://one.newrelic.com> → API keys. |

No token is needed for anything that goes through SSH (containers, origin
`/up` probe, cloudflared metrics + logs). All secrets live in `.env`, which is
gitignored.

---

## The scripts

| Script | Answers | One-liner |
|--------|---------|-----------|
| **`pi_watch.py`** | Is a pipeline run starving the box? Which container eats the CPU? Is `/up` slow with the tunnel bypassed? | `python pi_watch.py` (live) |
| **`tunnel_probe.py`** | Is this a real tunnel fault, or the origin-cancel symptom? cloudflared metrics + classified logs. | `python tunnel_probe.py --since 30m` |
| **`cf_analytics.py`** | Cloudflare's view: tunnel health + edge-5xx vs origin status (did the origin answer at all?). | `python cf_analytics.py --since-min 60` |
| **`edge_vs_origin.py`** | Same `/up`, edge vs origin-direct, side by side. Localises the latency. | `python edge_vs_origin.py --watch 5` |
| **`newrelic_query.py`** | The saturation signals Sentry can't show: latency, throughput, **queue time**, error rate. | `python newrelic_query.py --since-min 30` |

### What to run when

- **A run is happening and the site feels slow** → `pi_watch.py` live. Watch the
  `job` container's CPU and the `/up` latency. If `/up` is slow here (tunnel
  already bypassed), it's origin saturation — stop suspecting Cloudflare.
- **"Is it the tunnel?"** → `tunnel_probe.py`. If you see only
  `origin canceled` and **no** edge faults, the tunnel is healthy. If you see
  `edge reconnect` / `dial` failures, it's genuinely tunnel-side.
- **Want Cloudflare's own numbers** → `cf_analytics.py`. Edge 504 with a
  **silent origin** = the origin/tunnel never returned; edge 504 with a real
  origin status = Rails actually errored (then check New Relic/Sentry).
- **Confirm the hop** → `edge_vs_origin.py`. Big edge time + small origin time =
  the edge/tunnel hop; both slow = origin.
- **Historical correlation** → `newrelic_query.py`. Watch `queue_ms` climb while
  `avg_ms` stays flat — requests waiting for a Puma thread.

---

## Continuous monitoring (Beszel & auditd)

The Python diagnostic scripts are pull-on-demand tools for active investigations.
For continuous, always-on host and container monitoring, Sway runs Beszel as Kamal
accessories on the serving host.

Beszel provides persistent telemetry, per-container metrics, and historical
graphs with near-zero overhead, avoiding the resource weight of a full Prometheus
and Grafana stack on single-host hardware.

### Architecture and isolation guarantees

The setup consists of three Kamal accessories defined in `config/deploy.yml`:

- **`beszel` (Hub UI & Time-Series DB)**: Runs `henrygd/beszel:0.21.0`. Hard-capped
  at 0.25 CPU and 128 MB RAM (`cpus: "0.25"`, `memory: "128m"`). Stores metrics
  history and database files on the SSD volume at `<SWAY_STORAGE_DIR>/beszel`
  (mounted into the container at `/beszel_data`) to prevent flash memory wear on
  a single-board computer's memory card.
- **`beszel_agent` (Metrics Collector)**: Runs `henrygd/beszel-agent:0.21.0`.
  Hard-capped at 0.25 CPU and 64 MB RAM (`cpus: "0.25"`, `memory: "64m"`). Mounts
  the host Docker daemon (`/var/run/docker.sock:/var/run/docker.sock:ro`) and SSD
  storage (`<SWAY_STORAGE_DIR>:/extra-filesystems/sda1:ro`) strictly read-only so
  it cannot mutate containers or production data.
- **`auditd` (Host Exfiltration Auditing)**: Runs `alpine:3.21` with `network: "host"`,
  `pid: "host"`, `cap-add: ["AUDIT_CONTROL", "AUDIT_READ"]`, hard-capped at 0.10 CPU and
  32 MB RAM (`cpus: "0.10"`, `memory: "32m"`). It enforces non-blocking kernel audit rules
  (`--backlog_wait_time 0`, `-f 1`) and emits alerts for access to `<SWAY_STORAGE_DIR>`, `<SWAY_KEYFILE_PATH>`, or `/var/run/docker.sock`.

All accessories run on the serving host under tight resource limits that guarantee
they cannot starve core application workloads (`web`, `job`, `litestream`, or
`cloudflare_tunnel`).

### Network boundary

Access is restricted strictly to private networks:

- **Hub UI**: Port 8090 publishes exclusively to `SWAY_HOST` (LAN IP) and, when
  configured, to `SWAY_TAILSCALE_IP` (Tailscale mesh IP). It never binds `0.0.0.0`,
  has no `proxy` block, and is never exposed through the Cloudflare tunnel or the
  public internet.
- **Dynamic Tailscale auto-detection**: `./scripts/deploy.sh` automatically probes
  for active Tailscale connectivity on both the local workstation and the serving host
  using a 2-second fail-open timeout before Kamal deploy dispatch. If a valid
  `100.64.0.0/10` CGNAT IPv4 address is detected on both hosts, it exports
  `SWAY_TAILSCALE_IP` so the Beszel hub binds to the Tailscale mesh interface. If
  Tailscale is disabled, unreachable, or times out, the probe fails open and the deploy
  falls back to LAN-only `SWAY_HOST:8090` without interrupting the deployment.
- **Tailscale interface safety**: When Tailscale is not running on the serving host, leave
  `SWAY_TAILSCALE_IP` unset in `deploy/config/sway.env`. Docker will then bind only
  `SWAY_HOST:8090:8090` without attempting to bind a non-existent Tailscale network
  interface.
- **Agent collector**: Publishes no host ports whatsoever. The agent listens
  internally on port 45876 and communicates with the hub exclusively over the
  internal `kamal` Docker bridge network at `beszel-agent:45876`.

### Accessory lifecycle

Accessory deployment is automated through `./scripts/deploy.sh`:

- **Initial deploy (`./scripts/deploy.sh --initial-deploy`)**: Boots `cloudflare_tunnel`,
  `litestream`, `beszel`, `beszel_agent`, and `auditd` before running database seeding
  and score backfills.
- **Routine redeploy (`./scripts/deploy.sh`)**: Reboots `cloudflare_tunnel`,
  `litestream`, `beszel`, `beszel_agent`, and `auditd` to ensure running containers
  pick up updated configurations or host state.

### First-time bootstrap and setup flow

Setting up Beszel on a fresh deployment requires registering the agent key in
your secret store (Bitwarden in the reference setup) and pairing the agent container with the hub:

1. **Configure Tailscale IP (Optional)**: If Tailscale runs on the serving host, define
   `SWAY_TAILSCALE_IP` in `deploy/config/sway.env`. Otherwise, leave it unset so the
   hub binds LAN only.
2. **Pre-seed the secret**: `.kamal/secrets-common` fetches `BESZEL_AGENT_KEY`
   on every deploy. Before the initial deploy, create the `BESZEL_AGENT_KEY` item in
   your secret store (using a temporary placeholder value if the hub has never booted)
   and sync it (`bw sync` with Bitwarden).
3. **Run Initial Deploy**: Execute `./scripts/deploy.sh --initial-deploy` to boot
   the stack and launch the `beszel` hub accessory.
4. **Create Admin Account & Obtain Key**:
   - Open `http://<SWAY_HOST>:8090` in your browser (or `http://<SWAY_TAILSCALE_IP>:8090`
     if using Tailscale).
   - Follow the prompts to create the initial administrator account (email and password).
   - Click **Add System**, which displays the Hub's Ed25519 public key.
   - Copy this public key, update the `BESZEL_AGENT_KEY` item in your secret store
     with the copied key, and sync it.
   - Re-run `./scripts/deploy.sh` (or run `kamal accessory reboot beszel_agent`) to
     provide the agent container with the valid key.
5. **Register the host in the Hub**:
   - In the Beszel Hub **Add System** dialog, enter:
     - **Name**: any label, e.g. `<your-host-name>`
     - **Host/IP**: `beszel-agent` (resolves over the internal `kamal` Docker bridge)
     - **Port**: `45876`
   - Save the system. The hub will connect to the agent container and begin recording
     system and container telemetry.

### Day-2 operations

Manage the monitoring accessories using standard Kamal commands from your development
machine:

```bash
# View container logs
kamal accessory logs beszel
kamal accessory logs beszel_agent
kamal accessory logs auditd

# Reboot containers after configuration or key changes
kamal accessory reboot beszel
kamal accessory reboot beszel_agent
kamal accessory reboot auditd

# Check accessory container status
kamal accessory details beszel
kamal accessory details beszel_agent
kamal accessory details auditd
```

### Host exfiltration auditing events

The `auditd` accessory monitors sensitive host resources. Access to them generates an audit event tagged with one of three keys:

- **`sway_storage_access`**: Triggered when a process reads, writes, or alters permissions in `<SWAY_STORAGE_DIR>`.
- **`sway_keyfile_access`**: Triggered when a process touches the Litestream Google Cloud Storage credential keyfile at `<SWAY_KEYFILE_PATH>`.
- **`sway_docker_sock_access`**: Triggered when a process interacts with the host Docker socket (`/var/run/docker.sock`).

These events are written to the container log stream and forwarded asynchronously to Sentry. They can be inspected directly in the Beszel container log viewer or via the command line:

```bash
kamal accessory logs auditd
```

