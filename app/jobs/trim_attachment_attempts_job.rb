# frozen_string_literal: true

# @lat: [[attachment-attempts#Attachment download attempts#Retention sweep]]
class TrimAttachmentAttemptsJob < ApplicationJob
  queue_as :background

  RETENTION_DAYS = 30
  BATCH_SIZE = 500

  def perform
    cutoff = RETENTION_DAYS.days.ago
    deleted_total = 0

    loop do
      ids = PipelineActivityLogEntry
        .where(event_type: "attachment_download_attempt")
        .where("created_at < ?", cutoff)
        .limit(BATCH_SIZE)
        .pluck(:id)
      break if ids.empty?

      deleted = PipelineActivityLogEntry.where(id: ids).delete_all #: Integer
      deleted_total += deleted
      break if ids.size < BATCH_SIZE
    end

    SwayLogging.info(
      "[TrimAttachmentAttemptsJob] complete deleted=#{deleted_total} " \
      "retention_days=#{RETENTION_DAYS} cutoff_at=#{cutoff.iso8601}"
    )
    deleted_total
  end
end
