# frozen_string_literal: true

# @lat: [[retag-inferred-legislator-votes-cleanup#What it touches]]
class RetagInferredLegislatorVotesJob < ApplicationJob
  queue_as :background

  # @lat: [[retag-inferred-legislator-votes-cleanup#Why the boot initializer needs no duplicate guard of its own]]
  limits_concurrency to: 1,
    key: ->(*_args, **_kwargs) { "retag_inferred_legislator_votes" },
    on_conflict: :discard

  # @lat: [[retag-inferred-legislator-votes-cleanup#What it touches]]
  SPONSOR_INFERENCE_SOURCES = %w[congress open_states].freeze

  def perform
    retag_baltimore_rows
    retag_congress_and_maryland_rows
  end

  private

  # @lat: [[retag-inferred-legislator-votes-cleanup#Why the Congress/Maryland recompute is delayed 30 seconds]]
  def retag_baltimore_rows
    LegislatorVote.where(source: "legistar", inferred: false)
      .update_all(inferred: true, updated_at: Time.current)
  end

  def retag_congress_and_maryland_rows
    scope = LegislatorVote.where(
      source: SPONSOR_INFERENCE_SOURCES,
      inferred: false,
      support: LegislatorVote::Support::FOR
    ).where.not(bill_id: bill_ids_with_roll_call_pointer)

    affected_bill_ids = scope.distinct.pluck(:bill_id)
    return if affected_bill_ids.empty?

    scope.update_all(inferred: true, updated_at: Time.current)

    # @lat: [[boot-time-backfills#Why the Congress and Maryland recompute is delayed 30 seconds]]
    affected_bill_ids.each do |bill_id|
      RecomputeBillInterestingScoreJob.set(wait: 30.seconds).perform_later(bill_id)
    end
  end

  def bill_ids_with_roll_call_pointer
    RollCall.where.not(house_roll_call_vote_number: nil)
      .or(RollCall.where.not(senate_roll_call_vote_number: nil))
      .select(:bill_id)
  end
end
