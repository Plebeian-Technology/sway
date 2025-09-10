# frozen_string_literal: true

class NotificationsController < ApplicationController
    def index
        render_component(
            Pages::NOTIFICATIONS,
            lambda { { subscriptions: current_user&.push_notification_subscriptions&.map(&:attributes) || [] } },
        )
    end
end
