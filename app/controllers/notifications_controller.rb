# frozen_string_literal: true

class NotificationsController < ApplicationController
  def index
    render inertia: Pages::NOTIFICATIONS,
      props: {
        # @lat: [[push-notification-subscription-design#Why to_builder withholds auth and p256dh]]
        subscriptions:
          InertiaRails.defer do
            current_user&.push_notification_subscriptions&.map(
              &:to_sway_json
            ) || []
          end,
        sms_notifications_enabled: current_user&.sms_notifications_enabled,
        sms_phone: Sway::TwilioClient.display_from_phone,

        org_position_taken:
          current_user&.notification_preferences&.find_by(
            key: "org_position_taken"
          )&.enabled,
        org_position_cadence_default: current_user&.org_position_cadence_default,
        notify_on_new_position_default:
          current_user&.notify_on_new_position_default,
        notify_on_support_change_default:
          current_user&.notify_on_support_change_default,
        notify_on_summary_change_default:
          current_user&.notify_on_summary_change_default
      }
  end

  # @lat: [[tab-preserving-redirect-and-stale-element-lookups#Why every NotificationsController redirect names its tab explicitly]]
  PUSH_TAB = "push"
  SMS_TAB = "sms"
  ORGANIZATIONS_TAB = "organizations"

  def update_settings
    if current_user.update(notification_params)
      redirect_to notifications_path(tab: SMS_TAB),
        notice: "Notification preferences updated."
    else
      # @lat: [[tab-preserving-redirect-and-stale-element-lookups#Why every NotificationsController redirect names its tab explicitly]]
      redirect_to notifications_path(tab: SMS_TAB), inertia: {errors: current_user.errors}
    end
  end

  # @lat: [[org-notification-cascade-and-defaults#Org-notification cascade and defaults]]
  def update_organization_defaults
    bool = ActiveModel::Type::Boolean.new

    # @lat: [[org-notification-cascade-and-defaults#Why the master toggle checks presence, not truthiness]]
    user_params = params[:user]
    if user_params.respond_to?(:key?) && user_params.key?(:org_position_taken)
      current_user.notification_preferences
        .find_or_create_by!(key: "org_position_taken")
        .update!(enabled: bool.cast(user_params[:org_position_taken]))
    end

    unless current_user.apply_org_notification_defaults!(organization_defaults_params)
      redirect_to notifications_path(tab: ORGANIZATIONS_TAB), inertia: {errors: current_user.errors}
      return
    end

    redirect_to notifications_path(tab: ORGANIZATIONS_TAB),
      notice: "Organization notification defaults updated."
  end

  private

  def notification_params
    params.require(:user).permit(:sms_notifications_enabled)
  end

  def organization_defaults_params
    params.require(:user).permit(
      :org_position_cadence_default,
      :notify_on_new_position_default,
      :notify_on_support_change_default,
      :notify_on_summary_change_default
    )
  end
end
