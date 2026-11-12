# @lat: [[home-feed#Live feed updates]]
class FeedBroadcaster
  def self.notify(users)
    Array(users).each do |user|
      ActionCable.server.broadcast("feed_#{user.id}", {type: "feed_updated"})
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
