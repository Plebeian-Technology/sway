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
      render json: { sms_notifications_enabled: current_user.sms_notifications_enabled }, status: :ok
    else
      render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def notification_params
    params.require(:user).permit(:sms_notifications_enabled)
  end
end
