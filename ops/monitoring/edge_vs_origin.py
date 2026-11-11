#!/usr/bin/env python3
"""edge_vs_origin — the same /up request, two paths, side by side.

Times GET /up through Cloudflare (what a user gets) against an origin-direct hit
over SSH (kamal-proxy, tunnel bypassed). The cleanest live discriminator:

    big edge time, small origin time   -> the edge / tunnel hop is the cost
    both slow                          -> origin saturation

Usage:
    python edge_vs_origin.py
    python edge_vs_origin.py --watch 5
    python edge_vs_origin.py --url https://bill.sway.vote/up
"""
from __future__ import annotations

import argparse
import time
import urllib.error
import urllib.request

import _common as c
from rich.console import Console
from rich.table import Table
from rich.text import Text


# A real browser UA — Cloudflare bot management 403s a bare python-urllib UA,
# which would make every edge probe a false 403.
_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
       "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")


def time_public(url: str, timeout: int = 15):
    t0 = time.perf_counter()
    req = urllib.request.Request(url, headers={"User-Agent": _UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            r.read(64)
            return str(r.status), time.perf_counter() - t0
    except urllib.error.HTTPError as e:
        return str(e.code), time.perf_counter() - t0
    except Exception as e:  # noqa: BLE001
        return f"ERR {type(e).__name__}", time.perf_counter() - t0


def time_origin(host_header: str, up_path: str):
    # kamal-proxy is on the docker network only (cloudflared's path); resolve its
    # container IP in-remote and curl that, not the (unpublished) host port.
    proxy = c.env("PI_PROXY_CONTAINER", "kamal-proxy")
    cmd = (
        "PXY=$(docker inspect -f "
        "'{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "
        + proxy + " 2>/dev/null | awk '{print $1}') ; "
        "curl -s -o /dev/null -w '%{http_code} %{time_total}' "
        "-H 'Host: " + host_header + "' --max-time 15 \"http://$PXY" + up_path + "\""
    )
    try:
        out = c.ssh(cmd, timeout=20).strip().split()
    except RuntimeError as e:
        return f"ERR ({e})", None
    code = out[0] if out else "?"
    secs = float(out[1]) if len(out) > 1 and c.isfloat(out[1]) else None
    return code, secs


def _cell(code: str, secs) -> Text:
    ok = str(code) == "200"
    color = ("green" if ok and (secs or 9) < 0.5
             else "yellow" if ok and (secs or 9) < 2 else "red")
    label = f"{code}    {secs * 1000:.0f} ms" if secs is not None else f"{code}"
    return Text(label, style=color)


def one(console: Console, url: str, host_header: str, up_path: str) -> None:
    pc, pt = time_public(url)
    oc, ot = time_origin(host_header, up_path)
    t = Table.grid(padding=(0, 3))
    t.add_column(justify="right", style="dim")
    t.add_column()
    t.add_row("edge (cloudflare)", _cell(pc, pt))
    t.add_row("origin (kamal-proxy)", _cell(oc, ot))
    if pt is not None and ot is not None:
        t.add_row("edge − origin", Text(f"{(pt - ot) * 1000:.0f} ms"))
    console.print(t)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--url", default=None, help="public health URL")
    ap.add_argument("--watch", type=float, default=0)
    args = ap.parse_args()
    c.load_env()
    host_header = c.env("ORIGIN_HOST_HEADER", "app.sway.vote")
    up_path = c.env("ORIGIN_UP_PATH", "/up")
    url = args.url or f"https://{host_header}{up_path}"
    console = Console()
    while True:
        console.rule(time.strftime("%H:%M:%S"))
        one(console, url, host_header, up_path)
        if not args.watch:
            break
        time.sleep(args.watch)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
