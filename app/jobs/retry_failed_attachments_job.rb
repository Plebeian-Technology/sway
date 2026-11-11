# frozen_string_literal: true

# @lat: [[attachment-attempts#Attachment download attempts#Later retry selection rules]]
class RetryFailedAttachmentsJob < ApplicationJob
  queue_as :background

  LOOKBACK_WINDOW = 14.days
  MAX_LOOKBACK = LOOKBACK_WINDOW
  WAIT_WINDOW = 24.hours
  MAX_ATTEMPTS = 3

  PERMANENT_ERROR_PATTERNS = [
    /blocked url:/i,
    /too many redirects/i,
    /attachment has no download url/i,
    /attachment id invalid/i,
    /magic-byte check failed/i,
    /not a PDF/i,
    /over the .*?-byte cap/i,
    /TooLarge/i,
    /\AHTTP 4(?!(?:29)\b)\d\d\b/i
  ].freeze

  def perform
    candidates = select_retry_candidates
    retried_count = 0
    succeeded_count = 0

    candidates.each do |candidate|
      bill = candidate[:bill]
      next if LegislationPipelineRun.active_for_bill(bill).any?

      provisioning = bill.bill_llm_provisioning
      if provisioning&.testimony_attachments.is_a?(Array)
        already_succeeded = provisioning.testimony_attachments.any? do |entry|
          entry.is_a?(Hash) &&
            entry["attachment_id"].to_s == candidate[:attachment_id].to_s &&
            entry["download_status"] == "succeeded"
        end
        next if already_succeeded
      end

      retried_count += 1
      success = retry_attachment(candidate)
      succeeded_count += 1 if success
    rescue => e
      SwayLogging.error(
        "[RetryFailedAttachmentsJob] error retrying attachment #{candidate[:attachment_id]} for bill #{candidate[:bill_external_id]}: #{e.class} #{e.message}"
      )
    end

    SwayLogging.info(
      "[RetryFailedAttachmentsJob] complete evaluated=#{candidates.size} retried=#{retried_count} succeeded=#{succeeded_count}"
    )
    {evaluated: candidates.size, retried: retried_count, succeeded: succeeded_count}
  end

  # @lat: [[attachment-attempts#Attachment download attempts#Later retry selection rules]]
  def self.permanent_rejection?(error)
    err = error.to_s.strip
    return false if err.empty?

    PERMANENT_ERROR_PATTERNS.any? { |pattern| err.match?(pattern) }
  end

  # @lat: [[attachment-attempts#Attachment download attempts#Later retry selection rules]]
  def self.retryable_outcome?(outcome:, error:)
    return false if outcome == "succeeded"
    return true if outcome == "skipped_time_budget"

    if outcome == "failed"
      return false if permanent_rejection?(error)

      err = error.to_s.strip
      return true if err.start_with?("Faraday::") || err.include?("Faraday::")
      return true if err.match?(/\AHTTP (?:429|5\d\d)\b/)
      return true if err.match?(/ceiling|timeout|timed out|TooSlow/i)
      return true if err.start_with?("write failed:")

      SwayLogging.warn("[RetryFailedAttachmentsJob] Unrecognized error not eligible for retry: #{err[0, 100]}")
      return false
    end

    false
  end

  private

  def select_retry_candidates
    cutoff = Time.current - LOOKBACK_WINDOW
    wait_cutoff = Time.current - WAIT_WINDOW

    entries = PipelineActivityLogEntry
      .where(event_type: "attachment_download_attempt")
      .order(created_at: :asc, id: :asc)
      .to_a

    groups = entries.group_by do |entry|
      subject_id = entry.subject_id.to_s
      att_id = entry.payload.is_a?(Hash) ? entry.payload["attachment_id"].to_s : ""
      [subject_id, att_id]
    end

    candidates = []

    groups.each do |(subject_id, att_id), group_entries|
      next if subject_id.blank? || att_id.blank?
      next if group_entries.size >= MAX_ATTEMPTS
      next if group_entries.first.created_at < cutoff

      last_entry = group_entries.last
      next if last_entry.created_at > wait_cutoff

      payload = last_entry.payload
      next unless payload.is_a?(Hash)

      outcome = payload["outcome"] || payload["status"]
      error = payload["error"]

      next unless self.class.retryable_outcome?(outcome: outcome, error: error)

      bill = Bill.find_by(id: subject_id)
      next if bill.nil?

      candidates << {
        bill: bill,
        bill_external_id: payload["bill_external_id"] || bill.external_id,
        attachment_id: att_id,
        filename: payload["filename"],
        url: payload["url"]
      }
    end

    candidates
  end

  def retry_attachment(candidate)
    service = FetchHearingsService.new(bill: candidate[:bill])
    service.retry_single_attachment!(
      attachment_id: candidate[:attachment_id],
      url: candidate[:url],
      filename: candidate[:filename]
    )
  end
end
