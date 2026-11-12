# @lat: [[home-feed#Live feed updates]]
class FeedChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_user.nil?

    stream_from "feed_#{current_user.id}"
  end

  def unsubscribed
  end
end
