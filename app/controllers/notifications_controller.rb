class NotificationsController < ApplicationController
  def index
    T.unsafe(self).render_notifications(lambda do
      {
        push: current_user&.push_notification_subscription&.attributes
      }
    end)
  end
end
