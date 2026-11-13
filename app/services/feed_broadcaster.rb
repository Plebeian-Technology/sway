# @lat: [[home-feed#Live feed updates]]
class FeedBroadcaster
  def self.notify(user_ids)
    Array(user_ids).each do |user_id|
      ActionCable.server.broadcast("feed_#{user_id}", {type: "feed_updated"})
    end
  end

  def self.users_for_locale(sway_locale)
    User
      .joins(user_legislators: :legislator)
      .where(user_legislators: {active: true})
      .where(legislators: {sway_locale_id: sway_locale.id})
      .distinct
  end
end
