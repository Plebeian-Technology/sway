#!/usr/bin/env python3
"""newrelic_query — APM latency / throughput / queue time via NerdGraph NRQL.

Sentry only captures exceptions, which is why a 504-without-errors looks empty
there. This pulls the SATURATION signals instead: response time, throughput,
request queue time (queueDuration), and error rate. queueDuration climbing while
duration stays flat is the classic "requests waiting for a Puma thread" tell.

Needs NEW_RELIC_USER_KEY (NRAK-...) + NEW_RELIC_ACCOUNT_ID (see .env.example).

Usage:
    python newrelic_query.py
    python newrelic_query.py --since-min 120 --app Sway
    python newrelic_query.py --nrql "SELECT count(*) FROM Transaction FACET name SINCE 30 minutes ago"
"""
from __future__ import annotations

import argparse

import _common as c
from rich.console import Console
from rich.table import Table

NERDGRAPH = "https://api.newrelic.com/graphql"
DEFAULT_NRQL = (
    "SELECT count(*) AS reqs, average(duration)*1000 AS avg_ms, "
    "percentile(duration, 95)*1000 AS p95_ms, max(duration)*1000 AS max_ms, "
    "average(queueDuration)*1000 AS queue_ms, "
    "percentage(count(*), WHERE error IS true) AS error_pct "
    "FROM Transaction {where} SINCE {since} MINUTES AGO"
)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--since-min", type=int, default=30)
    ap.add_argument("--app", default=None, help="appName filter")
    ap.add_argument("--nrql", default=None, help="raw NRQL override")
    args = ap.parse_args()
    c.load_env()

    key = c.env("NEW_RELIC_USER_KEY", required=True)
    acct = c.env("NEW_RELIC_ACCOUNT_ID", required=True)
    app = args.app or c.env("NEW_RELIC_APP_NAME")
    where = f"WHERE appName = '{app}'" if app else ""
    nrql = args.nrql or DEFAULT_NRQL.format(where=where, since=args.since_min)
    gql = ('{ actor { account(id: %s) { nrql(query: "%s") { results } } } }'
           % (acct, nrql.replace('"', '\\"')))

    console = Console()
    try:
        resp = c.http_json(NERDGRAPH, method="POST",
                           headers={"API-Key": key}, body={"query": gql})
    except RuntimeError as e:
        console.print(f"[red]{e}[/]")
        return
    if resp.get("errors"):
        console.print(f"[red]{resp['errors']}[/]")
        return

    results = resp["data"]["actor"]["account"]["nrql"]["results"]
    if not results:
        console.print("no data in window")
        return

    t = Table(title=f"APM — last {args.since_min}m" + (f"   [{app}]" if app else ""))
    for col in results[0]:
        t.add_column(col, justify="right")
    for row in results:
        t.add_row(*[f"{v:.1f}" if isinstance(v, (int, float)) else str(v)
                    for v in row.values()])
    console.print(t)


if __name__ == "__main__":
    main()
