# frozen_string_literal: true

class BackupLegislationArtifactsJob < ApplicationJob
  queue_as :background

  include Sentry::Cron::MonitorCheckIns

  class BackupIncomplete < StandardError; end

  MAX_REPORTED_FAILURES = 5

  # @lat: [[scheduled-job-monitoring#Why the slug is written out rather than derived]]
  MONITOR_SLUG = "backup-legislation-artifacts"
  # @lat: [[scheduled-job-monitoring#The crontab constant has to match the schedule file by hand]]
  MONITOR_CRONTAB = "0 7 * * *"
  # @lat: [[legislation-artifact-backup#Why the scheduled backup carries a cron monitor]]
  MONITOR_CHECKIN_MARGIN_MINUTES = 60
  # @lat: [[legislation-artifact-backup#Why the monitor is told how long a run may take]]
  MONITOR_MAX_RUNTIME_MINUTES = 480

  MONITOR_CONFIG = Sentry::Cron::MonitorConfig.from_crontab(
    MONITOR_CRONTAB,
    checkin_margin: MONITOR_CHECKIN_MARGIN_MINUTES,
    max_runtime: MONITOR_MAX_RUNTIME_MINUTES
  )

  # @lat: [[legislation-artifact-backup#Why the scheduled backup carries a cron monitor]]
  sentry_monitor_check_ins(
    slug: MONITOR_SLUG,
    monitor_config: MONITOR_CONFIG
  )

  def perform
    report = Legislation::ArtifactBackupService.new.call
    return if report.ok? && report.failed.empty?

    summary = format_failure_summary(report)
    Rails.logger.error(summary)
    raise BackupIncomplete, summary
  end

  private

  def format_failure_summary(report)
    summary = "legislation artifact backup finished #{report.status} — " \
      "#{report.files_found} found, #{report.uploaded_count} uploaded, " \
      "#{report.failed.size} failed, floor #{report.floor}"

    details = format_failed_details(report)
    return summary if details.blank?

    "#{summary} — #{details}"
  end

  def format_failed_details(report)
    return "" if report.failed.empty?

    items = report.failed.map { |key, err| "#{key} (#{err})" }
    if items.size > MAX_REPORTED_FAILURES
      "#{items.first(MAX_REPORTED_FAILURES).join(", ")} (+#{items.size - MAX_REPORTED_FAILURES} more)"
    else
      items.join(", ")
    end
  end
end
