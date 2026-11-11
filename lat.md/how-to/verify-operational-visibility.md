---
lat:
  mode: how-to
---
# Verify operational visibility

How an operator verifies Sway system health using the consolidated verification script, inspects New Relic APM metrics, and configures Cloudflare Health Checks for external availability alerting.

## Running the consolidated health script

The operations verification script runs automated checks across public HTTP endpoints, Litestream database replication, and background worker state.

The script executes locally or against a remote deployment URL:

```bash
./scripts/verify-operations.sh https://sway.vote
```

The script evaluates four operational health signals:

- Public health probe: validates HTTP 200 status from `/up`.
- Deployment metadata: validates HTTP 200 and commit SHA metadata from `/version`.
- Litestream replication: verifies `ReplicationHeartbeat.singleton` has checked in within 30 minutes (`checked_at >= 30.minutes.ago`), has zero persistent stalls (`consecutive_stalls < 2`), and no persistent read failures (`consecutive_read_failures < 5`).
- Background job processing: verifies `SolidQueue::FailedExecution.count` remains within bounded thresholds (`failed_executions_count <= max_allowed_failures`).

The script emits structured JSON to stdout and exits with 0 on healthy and 1 on failure.

## Operational health JSON schema

The verification script emits machine-readable JSON to stdout reporting root health status, probe timestamps, and granular component check results.

The JSON payload follows this top-level and component structure:

- `status` (`string`): Overall system health status, evaluating to `"healthy"` (exit 0) when all component probes succeed, or `"unhealthy"` (exit 1) if any probe fails or degrades.
- `timestamp` (`string`): ISO 8601 UTC timestamp of execution (e.g. `"2026-01-01T00:00:00Z"`).
- `target_url` (`string`): The normalized base URL being probed (e.g. `"https://sway.vote"`).
- `checks.up_endpoint`:
  - `status` (`string`): `"ok"` if HTTP 200 is returned, `"fail"` otherwise.
  - `http_code` (`integer`): Numeric HTTP status code (e.g. `200`, `500`), or `0` on connection refusal, timeout, or DNS failure (RFC 8259-compliant, no leading zeros).
  - `url` (`string`): Full probe URL (`"${TARGET_URL}/up"`).
- `checks.version_endpoint`:
  - `status` (`string`): `"ok"` if HTTP 200 is returned, `"fail"` otherwise.
  - `http_code` (`integer`): Numeric HTTP status code, or `0` on network failure.
  - `url` (`string`): Full probe URL (`"${TARGET_URL}/version"`).
  - `metadata` (`object`): Serialized deployment payload (`sha`, `short_sha`, `version`, `deployed_at`), or `{}` on probe failure.
- `checks.replication_heartbeat`:
  - `status` (`string`): `"ok"` if recent check-in exists (`checked_at >= 30.minutes.ago`), `consecutive_stalls < 2`, and `consecutive_read_failures < 5`; `"stale"`, `"error"`, or `"unhealthy"` otherwise.
  - `checked_at` (`string|null`): ISO 8601 UTC timestamp of the last heartbeat check-in, or `null` if uninitialized or database unreachable.
  - `last_replica_txid` (`integer|null`): Most recent transaction ID written to the replica bucket, or `null`.
  - `consecutive_stalls` (`integer`): Count of consecutive checks where the replica transaction ID failed to advance while primary transactions occurred.
  - `consecutive_read_failures` (`integer`): Count of consecutive read failures listing the remote replica bucket.
- `checks.solid_queue`:
  - `status` (`string`): `"ok"` if failed jobs count is between `0` and `max_allowed_failures`; `"error"` or `"unhealthy"` if threshold exceeded or query failure.
  - `failed_executions_count` (`integer`): Current number of failed executions in `SolidQueue::FailedExecution`, or `-1` on database query error.
  - `max_allowed_failures` (`integer`): Maximum allowed failed executions before triggering unhealthy status (default `0`, configurable via `MAX_FAILED_JOBS`).

### Healthy output example

A healthy response occurs when all endpoint probes return HTTP 200, the replication heartbeat is fresh, and failed jobs remain within limits.

```json
{
  "status": "healthy",
  "timestamp": "2026-01-01T00:00:00Z",
  "target_url": "https://sway.vote",
  "checks": {
    "up_endpoint": {
      "status": "ok",
      "http_code": 200,
      "url": "https://sway.vote/up"
    },
    "version_endpoint": {
      "status": "ok",
      "http_code": 200,
      "url": "https://sway.vote/version",
      "metadata": {
        "version": null,
        "sha": "0000000000000000000000000000000000000000",
        "short_sha": "00000000",
        "previous_sha": null,
        "previous_short_sha": null,
        "deployed_at": null,
        "uncommitted_digest": null,
        "built_from_committed_tree": null
      }
    },
    "replication_heartbeat": {
      "status": "ok",
      "checked_at": "2026-01-01T00:00:00Z",
      "last_replica_txid": 1234,
      "consecutive_stalls": 0,
      "consecutive_read_failures": 0
    },
    "solid_queue": {
      "status": "ok",
      "failed_executions_count": 0,
      "max_allowed_failures": 0
    }
  }
}
```

### Unhealthy output example

When an endpoint connection times out or the host is down, the script formats numeric 0 status codes and flags overall failure.

```json
{
  "status": "unhealthy",
  "timestamp": "2026-01-01T00:01:00Z",
  "target_url": "http://127.0.0.1:19283",
  "checks": {
    "up_endpoint": {
      "status": "fail",
      "http_code": 0,
      "url": "http://127.0.0.1:19283/up"
    },
    "version_endpoint": {
      "status": "fail",
      "http_code": 0,
      "url": "http://127.0.0.1:19283/version",
      "metadata": {}
    },
    "replication_heartbeat": {
      "status": "unhealthy",
      "checked_at": null,
      "last_replica_txid": null,
      "consecutive_stalls": 0,
      "consecutive_read_failures": 0
    },
    "solid_queue": {
      "status": "unhealthy",
      "failed_executions_count": 0,
      "max_allowed_failures": 0
    }
  }
}
```

## Litestream replication heartbeat and staleness detection

Replication monitoring evaluates recent check-in freshness, continuous transaction stream progress, and storage bucket read connectivity.

The database replication monitoring architecture operates across two integrated layers:

1. **Background Heartbeat Worker (`ReplicationLagCheckJob`)**: Scheduled via Solid Queue cron (`MONITOR_CRONTAB = "*/15 * * * *"`), this job runs every 15 minutes. It inspects Litestream's remote replica position against local transaction progress and updates the singleton `ReplicationHeartbeat` record with the current timestamp (`checked_at`).
2. **Freshness & Staleness Threshold**: Because `ReplicationLagCheckJob` runs every 15 minutes, a check-in margin of 30 minutes (`MONITOR_CHECKIN_MARGIN_MINUTES = 30`) is enforced. If the background queue stalls, worker threads die, or SQLite locks prevent execution, `checked_at` stops advancing. The verification probe flags any `checked_at` older than 30 minutes as `"status": "stale"`, preventing dead replication watchdogs from silently reporting green.
3. **External Cron Monitoring**: In production, `ReplicationLagCheckJob` is enrolled in Sentry Cron Monitors (`sentry_monitor_check_ins`). If a check-in ping is not received within the 30-minute threshold, Sentry fires an out-of-band notification to operators.
4. **Error & Stall Alarms**: If the replica fails to advance across consecutive checks (`consecutive_stalls >= 2`) or cloud bucket listings fail repeatedly (`consecutive_read_failures >= 5`), `ReplicationLagCheckJob` emits Sentry alarms (`STALL_ALARM`, `READ_FAILURE_ALARM`), directing operators to recovery runbooks.

## Decoupled non-fate-sharing monitoring architecture

Operational alerting must not share fate with the monitored host, isolating external availability checks from local application runtimes.

Sway's monitoring topology is deliberately decoupled into non-fate-sharing layers:

- **Edge Availability Monitoring (Cloudflare Health Checks)**: Probes ping `https://sway.vote/up` every 60 seconds from multiple geographic edge data centers around the world. Because Cloudflare edge nodes operate on independent power, network routes, and hardware, edge alerting fires immediately if the Raspberry Pi server suffers hardware failure, kernel crash, power outage, or ISP disconnection. An on-host monitoring tool would die alongside the host and fail to alert.
- **Application Performance Monitoring (New Relic APM)**: The `newrelic_rpm` agent (`config/newrelic.yml`) instruments Puma web threads, database query execution, and background worker queues with `transaction_events`, `distributed_tracing`, and `span_events` enabled and `transaction_tracer.transaction_threshold` set to `0.5` seconds, streaming telemetry over outbound HTTPS to New Relic's SaaS cloud. If database lock contention, slow queries, or worker backlogs emerge, New Relic records latency distributions (p50, p95, p99) and slow transaction traces without consuming host compute.
- **Web vs Worker Process Decoupling**: Puma web threads (handling `/up` and `/version`) operate in separate processes from Solid Queue background workers (handling `ReplicationLagCheckJob`). While `/up` verifies that the web server can accept HTTP traffic and acquire a database connection, it does not prove that background jobs are progressing. Probing `ReplicationHeartbeat` and `SolidQueue::FailedExecution` through `scripts/verify-operations.sh` provides the complementary background assurance.

## Verification procedure

Follow these steps to verify operational health signals, inspect live telemetry dashboards, and configure external availability alerting.

1. Run `scripts/verify-operations.sh` against the production deployment (`https://sway.vote`) and verify the output reports root status `"healthy"` with exit code 0.
2. Verify that `replication_heartbeat.status` is `"ok"` and that `checked_at` is within the last 30 minutes.
3. Inspect the New Relic APM dashboard for the production application to confirm active telemetry, response time percentiles, and throughput.
4. Access the Cloudflare management console for the `sway.vote` domain and open the Traffic > Health Checks panel.
5. Create a new Health Check targeting `https://sway.vote/up` using a 60-second probe interval and a 5-second timeout threshold.
6. Configure alerting notification channels to dispatch email or webhook notifications when consecutive edge probes fail.
7. Verify that an alert is delivered when probes fail, confirming that uptime monitoring operates independently of host fate-sharing.

## Outcome

Multi-layered operational visibility guarantees rapid fault detection across edge routing, container health, database replication, and worker queues.

Operators maintain non-fate-sharing visibility across global Cloudflare edge probes, in-depth New Relic APM telemetry, and automated verification scripts with strict replication staleness thresholds.
