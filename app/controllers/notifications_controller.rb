# frozen_string_literal: true

class NotificationsController < ApplicationController
  def index
    T.unsafe(self).render_notifications(lambda do
      {
        subscriptions: current_user&.push_notification_subscriptions&.map(&:attributes) || []
      }
    end)
  end
end
