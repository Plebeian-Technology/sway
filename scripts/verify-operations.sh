#!/usr/bin/env bash
#
# scripts/verify-operations.sh
#
# Consolidated operational health check for Sway:
# 1. /up endpoint HTTP status (200 OK)
# 2. /version endpoint metadata (200 OK)
# 3. Litestream replication heartbeat (ReplicationHeartbeat.singleton)
# 4. Solid Queue failed execution count (SolidQueue::FailedExecution.count)
#
# Usage:
#   ./scripts/verify-operations.sh [TARGET_URL]
#   SWAY_BASE_URL=https://sway.vote ./scripts/verify-operations.sh
#
# Exits 0 on healthy, 1 on failure. Emits structured JSON summary to stdout.
#
# @lat: [[verify-operational-visibility#Running the consolidated health script]]

set -uo pipefail

TARGET_URL="${1:-${SWAY_BASE_URL:-https://sway.vote}}"
TARGET_URL="${TARGET_URL%/}"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
MAX_FAILED_JOBS="${MAX_FAILED_JOBS:-0}"
if [[ ! "$MAX_FAILED_JOBS" =~ ^[0-9]+$ ]]; then
    MAX_FAILED_JOBS=0
fi

MAX_HEARTBEAT_STALENESS_MINUTES="${MAX_HEARTBEAT_STALENESS_MINUTES:-30}"
if [[ ! "$MAX_HEARTBEAT_STALENESS_MINUTES" =~ ^[0-9]+$ ]]; then
    MAX_HEARTBEAT_STALENESS_MINUTES=30
fi

# Query HTTP status code via curl, safely normalizing network failures/timeouts to integer 0
query_http_status() {
    local url="$1"
    local raw_code
    raw_code=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || true)
    raw_code=$(echo "$raw_code" | tr -d '[:space:]')
    if [[ "$raw_code" =~ ^[0-9]+$ ]]; then
        echo "$((10#$raw_code))"
    else
        echo "0"
    fi
}

# 1. Probe /up endpoint
UP_HTTP_CODE=$(query_http_status "${TARGET_URL}/up")
UP_OK=false
if [[ "$UP_HTTP_CODE" == "200" ]]; then
    UP_OK=true
fi

# 2. Probe /version endpoint
VERSION_HTTP_CODE=$(query_http_status "${TARGET_URL}/version")
VERSION_OK=false
if [[ "$VERSION_HTTP_CODE" == "200" ]]; then
    VERSION_OK=true
fi

# 3 & 4. Query Rails environment for Litestream heartbeat, Solid Queue, and Release metadata
RUBY_PROBE='
arg0 = ARGV[0].to_s.strip
arg1 = ARGV[1].to_s.strip
env_failed = ENV["MAX_FAILED_JOBS"].to_s.strip
env_stale = ENV["MAX_HEARTBEAT_STALENESS_MINUTES"].to_s.strip

max_allowed_failures = if arg0 =~ /^[0-9]+$/
  arg0.to_i
elsif env_failed =~ /^[0-9]+$/
  env_failed.to_i
else
  0
end

max_staleness_minutes = if arg1 =~ /^[0-9]+$/
  arg1.to_i
elsif env_stale =~ /^[0-9]+$/
  env_stale.to_i
else
  30
end

heartbeat_data = begin
  hb = ReplicationHeartbeat.singleton
  is_recent = hb.checked_at.present? && hb.checked_at >= max_staleness_minutes.minutes.ago
  is_unstalled = hb.consecutive_stalls < 2 && hb.consecutive_read_failures < 5 && hb.consecutive_empty_listings < 2
  hb_healthy = is_recent && is_unstalled

  status_str = if hb_healthy
    "ok"
  elsif !is_recent
    "stale"
  else
    "unhealthy"
  end

  {
    status: status_str,
    checked_at: hb.checked_at&.iso8601,
    last_replica_txid: hb.last_replica_txid,
    consecutive_stalls: hb.consecutive_stalls,
    consecutive_read_failures: hb.consecutive_read_failures,
    consecutive_empty_listings: hb.consecutive_empty_listings,
    stalled_since: hb.stalled_since&.iso8601,
    healthy: hb_healthy,
    error: nil
  }
rescue StandardError => e
  {
    status: "error",
    checked_at: nil,
    last_replica_txid: nil,
    consecutive_stalls: -1,
    consecutive_read_failures: -1,
    consecutive_empty_listings: -1,
    stalled_since: nil,
    healthy: false,
    error: e.message
  }
end

solid_queue_data = begin
  failed_jobs = SolidQueue::FailedExecution.count
  queue_healthy = failed_jobs >= 0 && failed_jobs <= max_allowed_failures
  {
    status: queue_healthy ? "ok" : "unhealthy",
    failed_executions_count: failed_jobs,
    max_allowed_failures: max_allowed_failures,
    healthy: queue_healthy,
    error: nil
  }
rescue StandardError => e
  {
    status: "error",
    failed_executions_count: -1,
    max_allowed_failures: max_allowed_failures,
    healthy: false,
    error: e.message
  }
end

release = begin
  Sway::Release.to_sway_json
rescue StandardError
  {}
end

payload = {
  heartbeat: heartbeat_data,
  solid_queue: solid_queue_data,
  release: release
}

puts "__SWAY_METRICS_START__"
puts payload.to_json
puts "__SWAY_METRICS_END__"
'

RUNNER_OUTPUT=""
if command -v dip >/dev/null 2>&1 && [[ -z "${SWAY_NO_DIP:-}" ]]; then
    RUNNER_OUTPUT=$(MAX_FAILED_JOBS="$MAX_FAILED_JOBS" MAX_HEARTBEAT_STALENESS_MINUTES="$MAX_HEARTBEAT_STALENESS_MINUTES" dip run rails runner "$RUBY_PROBE" "$MAX_FAILED_JOBS" "$MAX_HEARTBEAT_STALENESS_MINUTES" 2>/dev/null || true)
elif [[ -f "bin/rails" && -n "${SWAY_ALLOW_HOST_RAILS:-}" ]]; then
    RUNNER_OUTPUT=$(MAX_FAILED_JOBS="$MAX_FAILED_JOBS" MAX_HEARTBEAT_STALENESS_MINUTES="$MAX_HEARTBEAT_STALENESS_MINUTES" bin/rails runner "$RUBY_PROBE" "$MAX_FAILED_JOBS" "$MAX_HEARTBEAT_STALENESS_MINUTES" 2>/dev/null || true)
elif command -v bundle >/dev/null 2>&1 && [[ -n "${SWAY_ALLOW_HOST_RAILS:-}" ]]; then
    RUNNER_OUTPUT=$(MAX_FAILED_JOBS="$MAX_FAILED_JOBS" MAX_HEARTBEAT_STALENESS_MINUTES="$MAX_HEARTBEAT_STALENESS_MINUTES" bundle exec rails runner "$RUBY_PROBE" "$MAX_FAILED_JOBS" "$MAX_HEARTBEAT_STALENESS_MINUTES" 2>/dev/null || true)
fi

# Extract JSON from delimiter block
METRICS_JSON=""
if echo "$RUNNER_OUTPUT" | grep -q "__SWAY_METRICS_START__"; then
    METRICS_JSON=$(echo "$RUNNER_OUTPUT" | sed -n '/__SWAY_METRICS_START__/,/__SWAY_METRICS_END__/p' | grep -v '__SWAY_METRICS_' | head -n 1)
fi

HB_CHECKED_AT="null"
HB_TXID="null"
HB_STALLS=0
HB_READ_FAILS=0
HB_STATUS="unhealthy"
HB_HEALTHY=false

SQ_FAILURES=0
SQ_STATUS="unhealthy"
SQ_HEALTHY=false

RELEASE_JSON="{}"

if [[ -n "$METRICS_JSON" ]]; then
    HB_CHECKED_AT=$(echo "$METRICS_JSON" | sed -E 's/.*"checked_at":("[^"]*"|null).*/\1/' || echo "null")
    HB_TXID=$(echo "$METRICS_JSON" | sed -E 's/.*"last_replica_txid":([0-9]+|null).*/\1/' || echo "null")
    HB_STALLS=$(echo "$METRICS_JSON" | sed -E 's/.*"consecutive_stalls":([0-9-]+).*/\1/' || echo "0")
    HB_READ_FAILS=$(echo "$METRICS_JSON" | sed -E 's/.*"consecutive_read_failures":([0-9-]+).*/\1/' || echo "0")
    if [[ ! "$HB_STALLS" =~ ^-?[0-9]+$ ]]; then HB_STALLS=0; fi
    if [[ ! "$HB_READ_FAILS" =~ ^-?[0-9]+$ ]]; then HB_READ_FAILS=0; fi

    EXTRACTED_HB_STATUS=$(echo "$METRICS_JSON" | sed -E 's/.*"heartbeat":\{[^}]*"status":"([^"]*)".*/\1/' || true)
    if [[ "$EXTRACTED_HB_STATUS" =~ ^(ok|stale|error|unhealthy)$ ]]; then
        HB_STATUS="$EXTRACTED_HB_STATUS"
    fi
    if echo "$METRICS_JSON" | grep -q '"heartbeat":{[^}]*"healthy":true'; then
        HB_HEALTHY=true
    fi

    SQ_FAILURES=$(echo "$METRICS_JSON" | sed -E 's/.*"failed_executions_count":([0-9-]+).*/\1/' || echo "0")
    if [[ ! "$SQ_FAILURES" =~ ^-?[0-9]+$ ]]; then SQ_FAILURES=0; fi
    EXTRACTED_SQ_STATUS=$(echo "$METRICS_JSON" | sed -E 's/.*"solid_queue":\{[^}]*"status":"([^"]*)".*/\1/' || true)
    if [[ "$EXTRACTED_SQ_STATUS" =~ ^(ok|error|unhealthy)$ ]]; then
        SQ_STATUS="$EXTRACTED_SQ_STATUS"
    fi
    if echo "$METRICS_JSON" | grep -q '"solid_queue":{[^}]*"healthy":true'; then
        SQ_HEALTHY=true
    fi

    RELEASE_JSON=$(echo "$METRICS_JSON" | sed -E 's/.*"release":(\{[^}]*\}).*/\1/' || echo "{}")
fi

if [[ "$VERSION_OK" != "true" || "$RELEASE_JSON" != \{*\} ]]; then
    VERSION_METADATA="{}"
else
    VERSION_METADATA="$RELEASE_JSON"
fi

UP_STATUS="fail"
if [[ "$UP_OK" == "true" ]]; then
    UP_STATUS="ok"
fi

VERSION_STATUS="fail"
if [[ "$VERSION_OK" == "true" ]]; then
    VERSION_STATUS="ok"
fi

# Determine overall health status
OVERALL_STATUS="healthy"
EXIT_CODE=0

if [[ "$UP_OK" != "true" || "$VERSION_OK" != "true" || "$HB_HEALTHY" != "true" || "$SQ_HEALTHY" != "true" ]]; then
    OVERALL_STATUS="unhealthy"
    EXIT_CODE=1
fi

cat <<EOF
{
  "status": "$OVERALL_STATUS",
  "timestamp": "$TIMESTAMP",
  "target_url": "$TARGET_URL",
  "checks": {
    "up_endpoint": {
      "status": "$UP_STATUS",
      "http_code": $UP_HTTP_CODE,
      "url": "${TARGET_URL}/up"
    },
    "version_endpoint": {
      "status": "$VERSION_STATUS",
      "http_code": $VERSION_HTTP_CODE,
      "url": "${TARGET_URL}/version",
      "metadata": $VERSION_METADATA
    },
    "replication_heartbeat": {
      "status": "$HB_STATUS",
      "checked_at": $HB_CHECKED_AT,
      "last_replica_txid": $HB_TXID,
      "consecutive_stalls": $HB_STALLS,
      "consecutive_read_failures": $HB_READ_FAILS
    },
    "solid_queue": {
      "status": "$SQ_STATUS",
      "failed_executions_count": $SQ_FAILURES,
      "max_allowed_failures": $MAX_FAILED_JOBS
    }
  }
}
EOF

exit $EXIT_CODE
