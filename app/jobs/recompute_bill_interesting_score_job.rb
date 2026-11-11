# frozen_string_literal: true

# @lat: [[recompute-bill-interesting-score-job-design#Why jobs coalesce per bill with discard, not a queue]]
class RecomputeBillInterestingScoreJob < ApplicationJob
  queue_as :background

  limits_concurrency to: 1,
    key: ->(bill_id, **_kwargs) { "interesting_score_#{bill_id}" },
    on_conflict: :discard

  def perform(bill_id)
    bill = Bill.find_by(id: bill_id)
    return unless bill

    BillInterestingScoreCalculator.new(bill).call
  end
end
