class OnUserVoteUpdateScoresJob < ApplicationJob
  queue_as :background

  # @lat: [[vote-triggered-score-jobs-design#Why OnLegislatorVoteUpdateScoresJob recomputes from scratch instead of applying deltas]]
  limits_concurrency to: 1, key: ->(user_vote) { "scores_bill_#{user_vote.bill_id}" }

  def perform(user_vote)
    SwayLogging.info(
      "OnUserVoteUpdateScoresJob.perform - UserVote = #{user_vote.id}"
    )
    ScoreUpdaterService.new(user_vote).call
  end
end
