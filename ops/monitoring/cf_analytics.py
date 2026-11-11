#!/usr/bin/env python3
"""cf_analytics — Cloudflare's own view: tunnel health + edge-vs-origin 5xx.

Tunnel health via the cfd_tunnel REST API; the 5xx breakdown (edge status vs
origin status) via the GraphQL Analytics API. The decisive signal: a 504 at the
edge whose originResponseStatus is 0/blank means the origin NEVER answered —
which matches the connector's "context canceled" and points at origin
saturation, not the tunnel.

Read-only token needed (see .env.example):
    Account > Cloudflare Tunnel > Read    and    Zone > Analytics > Read

Usage:
    python cf_analytics.py                 # tunnel health + last 60m of 5xx
    python cf_analytics.py --since-min 180
    python cf_analytics.py --no-tunnel     # just the 5xx breakdown
"""
from __future__ import annotations

import argparse
import datetime as dt

import _common as c
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

CF_API = "https://api.cloudflare.com/client/v4"
CF_GQL = "https://api.cloudflare.com/client/v4/graphql"

GQL = """
query($zone: String!, $since: Time!, $until: Time!) {
  viewer {
    zones(filter: {zoneTag: $zone}) {
      httpRequestsAdaptiveGroups(
        limit: 100,
        filter: {datetime_geq: $since, datetime_leq: $until, edgeResponseStatus_geq: 500},
        orderBy: [count_DESC]
      ) {
        count
        dimensions { edgeResponseStatus originResponseStatus clientRequestHTTPHost }
      }
    }
  }
}
""".strip()


def _auth() -> dict:
    return {"Authorization": f"Bearer {c.env('CLOUDFLARE_API_TOKEN', required=True)}"}


def tunnel_health(console: Console) -> None:
    tid = c.env("CLOUDFLARE_TUNNEL_ID")
    if not tid:
        console.print(
            "[yellow]tunnel check skipped: CLOUDFLARE_TUNNEL_ID is not set in the "
            "environment or ops/monitoring/.env[/]", soft_wrap=True)
        return

    acct = c.env("CLOUDFLARE_ACCOUNT_ID", required=True)
    try:
        info = c.http_json(f"{CF_API}/accounts/{acct}/cfd_tunnel/{tid}", headers=_auth())
        conns = c.http_json(
            f"{CF_API}/accounts/{acct}/cfd_tunnel/{tid}/connections", headers=_auth())
    except RuntimeError as e:
        console.print(Panel(str(e), title="tunnel health (API error)"))
        return

    status = (info.get("result") or {}).get("status", "?")
    style = "green" if status == "healthy" else "red"
    groups = conns.get("result") or []
    console.print(Panel(
        f"status: [{style}]{status}[/]    active connector groups: {len(groups)}",
        title=f"tunnel {tid[:8]}"))

    t = Table(title="connectors")
    t.add_column("colo")
    t.add_column("origin ip")
    t.add_column("opened")
    for grp in groups:
        for conn in grp.get("conns", []) or []:
            t.add_row(conn.get("colo_name", "?"),
                      str(grp.get("origin_ip", ""))[:18],
                      conn.get("opened_at", ""))
    if t.row_count:
        console.print(t)


def edge_origin_5xx(console: Console, minutes: int) -> None:
    zone = c.env("CLOUDFLARE_ZONE_ID", required=True)
    until = dt.datetime.now(dt.timezone.utc)
    since = until - dt.timedelta(minutes=minutes)
    body = {"query": GQL, "variables": {
        "zone": zone,
        "since": since.replace(microsecond=0).isoformat(),
        "until": until.replace(microsecond=0).isoformat(),
    }}
    try:
        resp = c.http_json(CF_GQL, method="POST", headers=_auth(), body=body)
    except RuntimeError as e:
        console.print(Panel(str(e), title="5xx analytics (API error)"))
        return
    if resp.get("errors"):
        console.print(Panel(
            f"{resp['errors']}\n\nThe httpRequestsAdaptiveGroups dataset / "
            "originResponseStatus dimension may require a Pro+ plan; adjust the "
            "GQL query if your plan returns a schema error.",
            title="GraphQL errors"))
        return

    zones = resp["data"]["viewer"]["zones"]
    groups = zones[0]["httpRequestsAdaptiveGroups"] if zones else []
    if not groups:
        console.print(Panel(f"no 5xx at the edge in the last {minutes}m", title="5xx"))
        return

    t = Table(title=f"edge 5xx vs origin status — last {minutes}m")
    t.add_column("edge")
    t.add_column("origin")
    t.add_column("host")
    t.add_column("count", justify="right")
    for g in groups:
        d = g["dimensions"]
        origin = str(d.get("originResponseStatus"))
        silent = origin in ("0", "None", "", "null")
        origin_cell = (origin + "  (origin silent)") if silent else origin
        t.add_row(str(d["edgeResponseStatus"]), origin_cell,
                  d.get("clientRequestHTTPHost", ""), str(g["count"]))
    console.print(t)
    console.print(Panel(
        "edge 5xx with a SILENT origin = the origin/tunnel never returned a "
        "response (matches 'context canceled'). edge 5xx WITH a real origin "
        "status = Rails actually answered with an error — check Sentry/New Relic.",
        title="read"))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--since-min", type=int, default=60)
    ap.add_argument("--no-tunnel", action="store_true")
    ap.add_argument("--no-5xx", action="store_true")
    args = ap.parse_args()
    c.load_env()
    console = Console()
    if not args.no_tunnel:
        tunnel_health(console)
    if not args.no_5xx:
        edge_origin_5xx(console, args.since_min)


if __name__ == "__main__":
    main()
