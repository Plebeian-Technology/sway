# frozen_string_literal: true

# @lat: [[activity-log-stream#What the hook owns]]
module BillCreator
  class ActivityLogPage
    PAGE_SIZE = 50

    def self.call(bill:, subject:, severity:, window:, cursor:)
      filters = filters_from(subject:, severity:, window:)

      scope = PipelineActivityLogEntry.recent_first

      if filters[:subject] == "this_bill" && bill&.id
        bill_ids = bill.legislation_pipeline_runs.pluck(:id).map(&:to_s)
        scope = scope.where(
          "(subject_type = 'Bill' AND subject_id = ?) OR " \
          "(subject_type = 'LegislationPipelineRun' AND subject_id IN (?))",
          bill.id.to_s,
          bill_ids.presence || ["__none__"]
        )
      end

      if filters[:severity] == "errors"
        scope = scope.errors_only
      end

      case filters[:window]
      when "24h"
        scope = scope.since(24.hours.ago)
      when "7d"
        scope = scope.since(7.days.ago)
      when "30d"
        scope = scope.since(30.days.ago)
      end

      cursor_ts, cursor_id = decode_cursor(cursor)
      if cursor_ts && cursor_id
        scope = scope.where(
          "(created_at < ?) OR (created_at = ? AND id < ?)",
          cursor_ts,
          cursor_ts,
          cursor_id
        )
      end

      entries = scope.limit(PAGE_SIZE + 1).to_a
      has_more = entries.size > PAGE_SIZE
      entries = entries.first(PAGE_SIZE)

      next_cursor =
        if has_more && entries.any?
          encode_cursor(entries.last)
        end

      {
        entries: entries.map { |e| PipelineActivityLogger.serialize_entry(e) },
        next_cursor: next_cursor,
        has_more: has_more
      }
    end

    def self.filters_from(subject:, severity:, window:)
      subject = subject.to_s
      severity = severity.to_s
      window = window.to_s

      {
        subject: %w[this_bill all_bills].include?(subject) ? subject : "all_bills",
        severity: %w[all errors].include?(severity) ? severity : "all",
        window: %w[24h 7d 30d all].include?(window) ? window : "7d"
      }
    end

    def self.encode_cursor(entry)
      Base64.urlsafe_encode64(
        "#{entry.created_at.iso8601(6)}|#{entry.id}",
        padding: false
      )
    end

    def self.decode_cursor(token)
      return [nil, nil] if token.blank?

      raw = Base64.urlsafe_decode64(token)
      parts = raw.split("|", 2)
      return [nil, nil] unless parts.size == 2

      ts = Time.iso8601(parts[0])
      id = Integer(parts[1])
      [ts, id]
    rescue ArgumentError, TypeError
      [nil, nil]
    end
  end
end
