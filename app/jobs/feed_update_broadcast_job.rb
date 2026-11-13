# frozen_string_literal: true

# @lat: [[home-feed#Live feed updates]]
class FeedUpdateBroadcastJob < ApplicationJob
  queue_as :background

  def perform(user_ids)
    ids = Array(user_ids).uniq
    return if ids.empty?

    FeedBroadcaster.notify(ids)
  end
end
