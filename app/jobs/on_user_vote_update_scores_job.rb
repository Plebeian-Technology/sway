class OnUserVoteUpdateScoresJob < ApplicationJob
  queue_as :background

  def perform(user_vote)
    Rails.logger.info(
      "OnUserVoteUpdateScoresJob.perform - UserVote = #{user_vote.id}",
    )
    ScoreUpdaterService.new(user_vote).run
  end
end
