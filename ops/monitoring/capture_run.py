#!/usr/bin/env python3
"""capture_run — time-series of origin saturation during a pipeline run.

Samples the Pi every --interval seconds for --duration seconds: per-container
CPU, origin /up status+latency (via kamal-proxy, tunnel bypassed), and the
solid_cable_messages count from the cable database. Prints the series + peaks.
Run this WHILE a pipeline run executes to capture the job-starves-web mechanism
behind the 504s.

Usage: python capture_run.py [--duration 180] [--interval 6]
"""
from __future__ import annotations

import argparse
import time

import _common as c
import pi_watch  # reuse probe_command() + parse()


def _cpu(stats_lines, needle):
    for line in stats_lines:
        if "|" in line:
            name, cpu, *_ = line.split("|")
            if needle in name:
                raw = cpu.strip().strip("%")
                return float(raw) if c.isfloat(raw) else None
    return None


def _fmt(v):
    return f"{v:.0f}" if isinstance(v, (int, float)) else "—"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--duration", type=int, default=180)
    ap.add_argument("--interval", type=float, default=6.0)
    args = ap.parse_args()
    c.load_env()
    cmd = pi_watch.probe_command()

    print(f"capturing every {args.interval:.0f}s for {args.duration}s ({c.pi_target()[2]})\n")
    print(f"{'time':>8} {'job%':>6} {'web%':>6} {'cfl%':>6} {'/up':>5} {'up_ms':>7} {'cable':>9}")
    print("-" * 56)

    peak_job = peak_web = worst_up = 0.0
    up_fail = samples = 0
    t_end = time.time() + args.duration
    while time.time() < t_end:
        t0 = time.time()
        try:
            data = pi_watch.parse(c.ssh(cmd, timeout=20))
        except Exception as e:
            print(f"{time.strftime('%H:%M:%S'):>8}  probe error: {e}")
            time.sleep(args.interval)
            continue
        stats = data.get("STATS", [])
        job, web, cfl = _cpu(stats, "job"), _cpu(stats, "web"), _cpu(stats, "cloudflared")
        up_line = next((l.strip() for l in data.get("UP", []) if l.strip()), "")
        parts = up_line.split()
        code = parts[0] if parts else "?"
        ms = float(parts[1]) * 1000 if len(parts) > 1 and c.isfloat(parts[1]) else None
        cable = next((l.strip() for l in data.get("CABLE", []) if l.strip()), "")

        if job is not None:
            peak_job = max(peak_job, job)
        if web is not None:
            peak_web = max(peak_web, web)
        if ms is not None:
            worst_up = max(worst_up, ms)
        if code not in ("200", "?"):
            up_fail += 1
        samples += 1

        print(f"{time.strftime('%H:%M:%S'):>8} {_fmt(job):>6} {_fmt(web):>6} "
              f"{_fmt(cfl):>6} {code:>5} {_fmt(ms):>7} {cable:>9}")
        dt = time.time() - t0
        if dt < args.interval:
            time.sleep(args.interval - dt)

    print("-" * 56)
    print(f"samples={samples}  peak job={peak_job:.0f}%  peak web={peak_web:.0f}%  "
          f"worst /up={worst_up:.0f}ms  /up non-200={up_fail}/{samples}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
