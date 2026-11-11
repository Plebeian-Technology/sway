# frozen_string_literal: true

# @lat: [[boot-time-backfills]]
unless Rails.env.test?
  Rails.application.config.after_initialize do
    next unless Sway::BootEnqueue.web_server_process?

    BackfillBillCategoriesJob.perform_later
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError,
    ActiveRecord::StatementInvalid, SolidQueue::Job::EnqueueError => e
    # @lat: [[boot-time-backfills#A failed enqueue is logged and left for the next boot]]
    SwayLogging.warn(
      "backfill_bill_categories.boot_enqueue_failed",
      error: e.class.name,
      message: e.message
    )
  end
end
