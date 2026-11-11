#!/usr/bin/env python3
"""pi_watch — live origin-saturation dashboard for the Sway Pi.

ONE SSH round-trip per refresh pulls, in a single shot:
  - per-container CPU / mem  (docker stats)
  - origin /up latency THROUGH kamal-proxy, with the tunnel bypassed
  - the latest legislation pipeline run
  - Solid Queue depth (ready / claimed)
  - solid_cable_messages row count + growth rate, from the cable database
    (broadcast pressure)

This is the workhorse for "is a pipeline run starving the box?" If /up is slow
here (tunnel already bypassed), the 504s are origin-side, not Cloudflare.

Usage:
    python pi_watch.py                 # live, refresh every 3s
    python pi_watch.py --interval 5
    python pi_watch.py --once          # single snapshot, no live view
"""
from __future__ import annotations

import argparse
import time

import _common as c
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text


def probe_command() -> str:
    """One remote command emitting marker-delimited sections."""
    host_header = c.env("ORIGIN_HOST_HEADER", "app.sway.vote")
    up_path = c.env("ORIGIN_UP_PATH", "/up")
    proxy = c.env("PI_PROXY_CONTAINER", "kamal-proxy")
    primary, queue, cable = c.primary_db(), c.queue_db(), c.cable_db()
    # kamal-proxy does NOT publish to the host — it's reachable only on the docker
    # network (cloudflared hits http://kamal-proxy:80). Resolve its container IP
    # in-remote and curl that: the exact path the tunnel uses, so the latency we
    # measure is the latency cloudflared sees.
    up_seg = (
        "PXY=$(docker inspect -f "
        "'{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "
        "__PROXY__ 2>/dev/null | awk '{print $1}') ; "
        "curl -s -o /dev/null -w '%{http_code} %{time_total}' "
        "-H 'Host: __HOST__' --max-time 10 \"http://$PXY__UP__\" ; echo"
    ).replace("__PROXY__", proxy).replace("__HOST__", host_header).replace("__UP__", up_path)
    return " ; ".join([
        "echo @@STATS@@",
        "docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}|{{.MemUsage}}'",
        "echo @@UP@@",
        up_seg,
        "echo @@PRUN@@",
        f"sqlite3 -readonly '{primary}' \"SELECT status, updated_at FROM legislation_pipeline_runs ORDER BY id DESC LIMIT 1;\" 2>/dev/null || true",
        "echo @@QUEUE@@",
        f"sqlite3 -readonly '{queue}' \"SELECT (SELECT count(*) FROM solid_queue_ready_executions),(SELECT count(*) FROM solid_queue_claimed_executions);\" 2>/dev/null || true",
        "echo @@CABLE@@",
        f"sqlite3 -readonly '{cable}' \"SELECT count(*) FROM solid_cable_messages;\" 2>/dev/null || true",
        "echo @@END@@",
    ])


def parse(blob: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    cur = None
    for line in blob.splitlines():
        s = line.strip()
        if s.startswith("@@") and s.endswith("@@"):
            cur = s.strip("@")
            sections[cur] = []
        elif cur is not None:
            sections[cur].append(line)
    return sections


def _cpu(pct: str) -> Text:
    raw = pct.strip().strip("%")
    if not c.isfloat(raw):
        return Text(pct)
    v = float(raw)
    # >100% means multi-core; on a 4-core Pi, one container near 300%+ starves
    # the rest. Green < 80, amber < 200, red beyond.
    color = "green" if v < 80 else "yellow" if v < 200 else "red"
    return Text(f"{v:6.1f}%", style=color)


def _first(section: list[str]) -> str:
    for line in section:
        if line.strip():
            return line.strip()
    return ""


def render(data: dict, state: dict) -> Group:
    now = time.time()

    # --- containers -------------------------------------------------------
    ct = Table(title="containers — docker stats", expand=True)
    ct.add_column("name")
    ct.add_column("cpu", justify="right")
    ct.add_column("mem%", justify="right")
    ct.add_column("mem", justify="right")
    rows = []
    for line in data.get("STATS", []):
        if "|" not in line:
            continue
        parts = (line.split("|") + ["", "", "", ""])[:4]
        rows.append(tuple(p.strip() for p in parts))

    def cpu_val(r):
        raw = r[1].strip("%")
        return float(raw) if c.isfloat(raw) else -1.0

    for name, cpu, memp, mem in sorted(rows, key=cpu_val, reverse=True):
        emphasis = "bold" if "job" in name else None
        ct.add_row(Text(name, style=emphasis), _cpu(cpu), memp, mem)
    if not rows:
        ct.add_row("no docker stats", "", "", "")

    # --- origin /up -------------------------------------------------------
    up_line = _first(data.get("UP", []))
    up_text = Text("no data", style="dim")
    if up_line:
        parts = up_line.split()
        code = parts[0] if parts else "?"
        secs = float(parts[1]) if len(parts) > 1 and c.isfloat(parts[1]) else None
        if secs is not None:
            state["up_max"] = max(state.get("up_max", 0.0), secs)
        ok = code == "200"
        color = ("green" if ok and (secs or 9) < 0.5
                 else "yellow" if ok and (secs or 9) < 2 else "red")
        shown = f"{secs * 1000:.0f} ms" if secs is not None else "—"
        worst = f"{state.get('up_max', 0.0) * 1000:.0f} ms"
        up_text = Text(f"HTTP {code}    {shown}    (worst this session: {worst})",
                       style=color)
    up = Panel(up_text, title="origin /up — via kamal-proxy, tunnel bypassed")

    # --- pipeline / queue / cable ----------------------------------------
    grid = Table.grid(padding=(0, 2))
    grid.add_column(justify="right", style="dim")
    grid.add_column()
    grid.add_row("latest pipeline run", _first(data.get("PRUN", [])) or "n/a")
    grid.add_row("queue ready|claimed", _first(data.get("QUEUE", [])) or "n/a")

    cable = _first(data.get("CABLE", []))
    rate = ""
    if cable.isdigit():
        cnt = int(cable)
        last = state.get("cable_last")
        if last:
            dc, dt = cnt - last[0], now - last[1]
            if dt > 0:
                rate = f"   ({dc / dt:+.1f}/s)"
        state["cable_last"] = (cnt, now)
    else:
        cable = "n/a"
    grid.add_row("solid_cable_messages", f"{cable}{rate}")
    meta = Panel(grid, title="pipeline / queue / cable — primary + queue + cable DBs")

    header = Text(f"{c.pi_target()[2]}    {time.strftime('%H:%M:%S')}", style="dim")
    return Group(header, ct, up, meta)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--interval", type=float, default=3.0)
    ap.add_argument("--once", action="store_true")
    args = ap.parse_args()
    c.load_env()
    cmd = probe_command()
    state: dict = {}

    def snapshot():
        try:
            return render(parse(c.ssh(cmd, timeout=20)), state)
        except Exception as e:  # noqa: BLE001 — surface any failure in the panel
            return Panel(Text(str(e), style="red"), title="probe error")

    if args.once:
        Console().print(snapshot())
        return

    with Live(snapshot(), refresh_per_second=4, screen=False) as live:
        while True:
            time.sleep(args.interval)
            live.update(snapshot())


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
