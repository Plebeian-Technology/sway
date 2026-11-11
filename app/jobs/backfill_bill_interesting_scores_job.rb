# frozen_string_literal: true

# @lat: [[backfill-bill-interesting-scores-job-design#Why there is no periodic/cron version]]
class BackfillBillInterestingScoresJob < ApplicationJob
  queue_as :background

  # @lat: [[backfill-bill-interesting-scores-job-design#Why the concurrency key is a fixed proc, not keyed per bill]]
  limits_concurrency to: 1,
    key: ->(*_args, **_kwargs) { "backfill_bill_interesting_scores" },
    on_conflict: :discard

  def perform
    # @lat: [[backfill-bill-interesting-scores-job-design#Why the concurrency key is a fixed proc, not keyed per bill]]
    unscored_bill_ids = SwayLocale.find_each.flat_map do |locale|
      Bill.current_session(locale)
        .where.not(id: BillInterestingScore.select(:bill_id))
        .pluck(:id)
    end

    return if unscored_bill_ids.empty?

    Bill.where(id: unscored_bill_ids).find_each do |bill|
      BillInterestingScoreCalculator.new(bill).call
    rescue => e
      # @lat: [[backfill-bill-interesting-scores-job-design#Why a bad bill does not abort the batch]]
      SwayLogging.log_exception(
        "backfill_bill_interesting_scores.bill_failed",
        exception: e,
        bill_id: bill.id
      )
    end
  end
end
