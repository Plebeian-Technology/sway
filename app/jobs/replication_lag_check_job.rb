# frozen_string_literal: true

# @lat: [[replication-lag-check-job-design#ReplicationHeartbeat holds exactly one row]]
class ReplicationLagCheckJob < ApplicationJob
  queue_as :background

  include Sentry::Cron::MonitorCheckIns

  # @lat: [[replication-lag-check-job-design#The monitor slug is set by hand]]
  MONITOR_SLUG = "replication-lag-check"
  # @lat: [[replication-lag-check-job-design#The crontab constant must match config/recurring.yml exactly]]
  MONITOR_CRONTAB = "*/15 * * * *"
  # @lat: [[replication-lag-check-job-design#The check-in margin is minutes, not slots or runs]]
  MONITOR_CHECKIN_MARGIN_MINUTES = 30

  MONITOR_CONFIG = Sentry::Cron::MonitorConfig.from_crontab(
    MONITOR_CRONTAB,
    checkin_margin: MONITOR_CHECKIN_MARGIN_MINUTES
  )

  sentry_monitor_check_ins(
    slug: MONITOR_SLUG,
    monitor_config: MONITOR_CONFIG
  )

  # @lat: [[replication-lag-check-job-design#Why there is no retry_on]]

  # @lat: [[replication-lag-check-job-design#Every alarm string is a frozen constant with no interpolated value]]
  STALL_ALARM = "Litestream has stopped copying the database. Go to the litestream accessory on the machine serving Sway. Recovery steps: docs/litestream-restore.md"
  READ_FAILURE_ALARM = "Sway cannot list the Litestream folder in the cloud bucket. Go to Sway's own Google credentials, not to the copier. Recovery steps: docs/litestream-restore.md"
  EMPTY_LISTING_ALARM = "Sway found no Litestream segment files under the path it was given. Go to SWAY_LITESTREAM_PATH in the deploy config. Recovery steps: docs/litestream-restore.md"
  RECOVERY_MESSAGE = "Litestream is copying the database again. How long it was stopped is on this event. Nothing to do."

  def perform
    now = Time.zone.now
    reading = Litestream::ReplicaPosition.new.call
    heartbeat = ReplicationHeartbeat.singleton
    previous_stalled_since = heartbeat.stalled_since

    decision = build_decision(reading: reading, heartbeat: heartbeat, now: now)
    write_heartbeat(heartbeat: heartbeat, decision: decision, checked_at: now)
    report(decision: decision, reading: reading, previous_stalled_since: previous_stalled_since)
  end

  private

  def build_decision(reading:, heartbeat:, now:)
    Litestream::ReplicationLagCheck.new(
      status: reading.status,
      position: reading.position,
      previous_position: heartbeat.last_replica_txid,
      consecutive_stalls: heartbeat.consecutive_stalls,
      consecutive_read_failures: heartbeat.consecutive_read_failures,
      consecutive_empty_listings: heartbeat.consecutive_empty_listings,
      stalled_since: heartbeat.stalled_since,
      now: now
    ).call
  end

  # @lat: [[replication-lag-check-job-design#write_heartbeat uses update_columns, never update! or save]]
  def write_heartbeat(heartbeat:, decision:, checked_at:)
    heartbeat.update_columns(
      checked_at: checked_at,
      updated_at: checked_at,
      last_replica_txid: decision.last_replica_txid,
      consecutive_stalls: decision.consecutive_stalls,
      consecutive_read_failures: decision.consecutive_read_failures,
      consecutive_empty_listings: decision.consecutive_empty_listings,
      stalled_since: decision.stalled_since
    )
  end

  # @lat: [[replication-lag-check-job-design#The three alarms route to three different machines]]
  def report(decision:, reading:, previous_stalled_since:)
    case decision.outcome
    when :stall
      report_stall(decision: decision, reading: reading) if decision.alarm
    when :read_failure
      report_read_failure(decision: decision, reading: reading) if decision.alarm
    when :empty_listing
      report_empty_listing(decision: decision, reading: reading) if decision.alarm
    when :recovered
      report_recovery(decision: decision, previous_stalled_since: previous_stalled_since)
    end
  end

  def report_stall(decision:, reading:)
    Sentry.capture_message(
      STALL_ALARM,
      level: :error,
      extra: {
        consecutive_stalls: decision.consecutive_stalls,
        last_replica_txid: decision.last_replica_txid,
        stalled_since: decision.stalled_since&.iso8601,
        bucket_name: reading.bucket_name,
        path: reading.path
      }
    )
  end

  # @lat: [[replication-lag-check-job-design#The recovery message's duration lives in extra:, not the text]]
  def report_recovery(decision:, previous_stalled_since:)
    Sentry.capture_message(
      RECOVERY_MESSAGE,
      level: :info,
      extra: {
        stalled_for_seconds: decision.stalled_for_seconds,
        stalled_since: previous_stalled_since&.iso8601,
        last_replica_txid: decision.last_replica_txid
      }
    )
  end

  # @lat: [[replication-lag-check-job-design#The read-failure alarm captures an exception, not a message]]
  def report_read_failure(decision:, reading:)
    Sentry.capture_exception(
      required_error(reading),
      fingerprint: ["litestream-read-failure"],
      extra: {
        alarm: READ_FAILURE_ALARM,
        consecutive_read_failures: decision.consecutive_read_failures,
        bucket_name: reading.bucket_name,
        path: reading.path
      }
    )
  end

  def report_empty_listing(decision:, reading:)
    Sentry.capture_message(
      EMPTY_LISTING_ALARM,
      level: :error,
      extra: {
        consecutive_empty_listings: decision.consecutive_empty_listings,
        bucket_name: reading.bucket_name,
        path: reading.path
      }
    )
  end

  # @lat: [[replication-lag-check-job-design#Why required_error exists]]
  def required_error(reading)
    error = reading.error
    raise ArgumentError, "ReplicationLagCheckJob#report_read_failure requires an error on the reading" if error.nil?

    error #: Exception
  end
end
