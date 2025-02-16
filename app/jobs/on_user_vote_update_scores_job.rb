class OnUserVoteUpdateScoresJob < ApplicationJob
  queue_as :background

  def perform(user_vote)
    Rails.logger.info("OnUserVoteUpdateScoresJob.args")
    Rails.logger.info(user_vote)
    ScoreUpdaterService.new(user_vote).run
  end
end
