#!/usr/bin/env python3
"""tunnel_probe — cloudflared health from its Prometheus metrics + logs.

Scrapes the cloudflared metrics endpoint (default :20241, seen in the connector
logs) by curling the container IP from the Pi host, then classifies recent
connector logs. The point is to DISTINGUISH:

  * "context canceled" on originService=kamal-proxy  -> the ORIGIN is too slow
    and the edge/client gave up. Tunnel is healthy. Go look at pi_watch.py.
  * "Retrying connection" / "Lost connection" / "dial tcp" -> a genuine
    tunnel-layer fault (CPU-starved connector, QUIC, or network).

Usage:
    python tunnel_probe.py                 # one-shot, last 20m of logs
    python tunnel_probe.py --since 1h
    python tunnel_probe.py --watch 10      # repeat every 10s
"""
from __future__ import annotations

import argparse
import re
import time

import _common as c
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

# cloudflared metric name prefixes worth surfacing (labels are tolerated).
HIGHLIGHT = [
    "cloudflared_tunnel_ha_connections",
    "cloudflared_tunnel_total_requests",
    "cloudflared_tunnel_request_errors",
    "cloudflared_tunnel_concurrent_requests_per_tunnel",
]

# label -> substring. "origin" labels are SYMPTOMS of a slow origin; the others
# are genuine tunnel faults.
LOG_PATTERNS = {
    "origin canceled (origin too slow)": "context canceled",
    "origin deadline exceeded": "context deadline exceeded",
    "origin dial/connect failed": "dial tcp",
    "edge reconnect": "Retrying connection",
    "edge connection lost": "Lost connection to the edge",
    "tunnel unregistered": "Unregistered tunnel connection",
    "QUIC buffer too small": "failed to sufficiently increase receive buffer",
}
ORIGIN_LABELS = {"origin canceled (origin too slow)", "origin deadline exceeded"}


def scrape_metrics() -> tuple[str, dict[str, str]]:
    name = c.docker_container("cloudflared", "PI_CLOUDFLARED_CONTAINER")
    ip = c.container_ip(name)
    port = c.env("CLOUDFLARED_METRICS_PORT", "20241")
    text = c.ssh(f"curl -s --max-time 8 http://{ip}:{port}/metrics", timeout=15)
    metrics: dict[str, str] = {}
    for line in text.splitlines():
        if line.startswith("#") or " " not in line:
            continue
        key, _, val = line.partition(" ")
        metrics[key] = val.strip()
    return name, metrics


def parse_logs(window: str) -> tuple[dict[str, int], dict[str, int], list[str]]:
    name = c.docker_container("cloudflared", "PI_CLOUDFLARED_CONTAINER")
    logs = c.ssh(f"docker logs --since {window} {name} 2>&1 | tail -n 3000", timeout=30)
    counts = {label: 0 for label in LOG_PATTERNS}
    dests: dict[str, int] = {}
    errs: list[str] = []
    for line in logs.splitlines():
        for label, needle in LOG_PATTERNS.items():
            if needle in line:
                counts[label] += 1
        if " ERR " in line or line.strip().startswith("ERR") or "ERR " in line:
            errs.append(line)
            m = re.search(r"dest=(\S+)", line)
            if m:
                dests[m.group(1)] = dests.get(m.group(1), 0) + 1
    return counts, dests, errs[-8:]


def render(console: Console, window: str) -> None:
    # --- metrics ----------------------------------------------------------
    try:
        name, metrics = scrape_metrics()
        mt = Table(title=f"cloudflared metrics — {name}")
        mt.add_column("metric")
        mt.add_column("value", justify="right")
        for prefix in HIGHLIGHT:
            matched = {k: v for k, v in metrics.items() if k.startswith(prefix)}
            if not matched:
                mt.add_row(prefix, "—")
            for k, v in sorted(matched.items()):
                mt.add_row(k, v)
        console.print(mt)
    except Exception as e:  # noqa: BLE001
        console.print(Panel(
            Text(f"metrics scrape failed: {e}\n"
                 "The metrics port is on the container's network, reached via its "
                 "IP from the Pi host. If this keeps failing, check "
                 "CLOUDFLARED_METRICS_PORT or PI_CLOUDFLARED_CONTAINER.",
                 style="yellow"),
            title="cloudflared metrics"))

    # --- logs -------------------------------------------------------------
    try:
        counts, dests, recent = parse_logs(window)
        lt = Table(title=f"connector log signals — last {window}")
        lt.add_column("signal")
        lt.add_column("count", justify="right")
        for label, n in counts.items():
            if n == 0:
                style = "dim"
            elif label in ORIGIN_LABELS:
                style = "yellow"   # symptom of slow origin, not a tunnel fault
            else:
                style = "red"      # genuine tunnel-layer trouble
            lt.add_row(Text(label, style=style), str(n))
        console.print(lt)

        if dests:
            dt = Table(title="canceled / failed request destinations")
            dt.add_column("dest")
            dt.add_column("hits", justify="right")
            for d, n in sorted(dests.items(), key=lambda x: -x[1])[:10]:
                dt.add_row(d, str(n))
            console.print(dt)

        if recent:
            console.print(Panel("\n".join(recent), title="recent ERR lines"))

        edge_faults = sum(
            counts[l] for l in counts if l not in ORIGIN_LABELS and counts[l]
            and ("edge" in l or "dial" in l or "unregistered" in l)
        )
        origin = sum(counts[l] for l in ORIGIN_LABELS)
        if origin and not edge_faults:
            console.print(Panel(Text(
                "Origin cancellations with NO edge faults -> the tunnel is healthy "
                "and the ORIGIN (kamal-proxy -> Puma) is too slow. Look at "
                "pi_watch.py, not Cloudflare.", style="bold green"), title="read"))
        elif edge_faults:
            console.print(Panel(Text(
                "Edge reconnects / dial failures present -> genuine tunnel-layer "
                "trouble (CPU-starved connector, QUIC, or network).",
                style="bold red"), title="read"))
    except Exception as e:  # noqa: BLE001
        console.print(Panel(Text(str(e), style="red"), title="log parse failed"))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--since", default="20m", help="log window, e.g. 20m, 1h")
    ap.add_argument("--watch", type=float, default=0, help="repeat every N seconds")
    args = ap.parse_args()
    c.load_env()
    console = Console()
    while True:
        console.rule(time.strftime("%H:%M:%S"))
        render(console, args.since)
        if not args.watch:
            break
        time.sleep(args.watch)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
