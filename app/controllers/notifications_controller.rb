# frozen_string_literal: true

class NotificationsController < ApplicationController
  def index
    render_component(
      Pages::NOTIFICATIONS,
      lambda do
        {
          subscriptions:
            current_user&.push_notification_subscriptions&.map(&:attributes) ||
              [],
          sms_notifications_enabled: current_user&.sms_notifications_enabled
        }
      end,
    )
  end

  def update_settings
    if current_user.update(notification_params)
      redirect_to notifications_path, notice: "Notification preferences updated."
    else
      redirect_to notifications_path, inertia: { errors: current_user.errors }
    end
  end

  private

  def notification_params
    params.require(:user).permit(:sms_notifications_enabled)
  end
end
