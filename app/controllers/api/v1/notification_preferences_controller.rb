# frozen_string_literal: true

module Api
  module V1
    class NotificationPreferencesController < BaseController
      def index
        prefs = current_user.notification_preferences.order(:key).to_a
        render json: prefs.map { |p| serialize(p) }
      end

      def update
        key = params[:key].to_s

        # @lat: [[org-notification-cascade-and-defaults#Org-notification cascade and defaults]]
        unless NotificationPreference::CANONICAL_KEYS.include?(key)
          return render_error(
            code: "unknown_preference",
            message: "Preference key not found",
            status: :not_found
          )
        end

        enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))

        pref = current_user.notification_preferences.find_or_create_by!(key: key)
        pref.update!(enabled: enabled)

        render json: serialize(pref)
      end

      # @lat: [[org-notification-cascade-and-defaults#Org-notification cascade and defaults]]
      def organization_defaults
        pref_row = current_user.notification_preferences.find_by(key: "org_position_taken")
        render json: serialize_organization_defaults(pref_row)
      end

      # @lat: [[org-notification-cascade-and-defaults#Org-notification cascade and defaults]]
      def update_organization_defaults
        bool = ActiveModel::Type::Boolean.new

        # @lat: [[org-notification-cascade-and-defaults#Why the master toggle checks presence, not truthiness]]
        master_val = params[:org_position_taken]
        unless master_val.nil?
          current_user.notification_preferences
            .find_or_create_by!(key: "org_position_taken")
            .update!(enabled: bool.cast(master_val))
        end

        unless current_user.apply_org_notification_defaults!(organization_defaults_params)
          return render_error(
            code: "validation_failed",
            message: current_user.errors.full_messages.to_sentence,
            status: :unprocessable_content
          )
        end

        pref_row = current_user.notification_preferences.find_by(key: "org_position_taken")
        render json: serialize_organization_defaults(pref_row)
      end

      private

      def serialize(pref)
        {
          key: pref.key,
          enabled: pref.enabled,
          updated_at: pref.updated_at.iso8601
        }
      end

      def serialize_organization_defaults(pref_row)
        {
          org_position_taken: pref_row&.enabled,
          org_position_cadence_default: current_user.org_position_cadence_default,
          notify_on_new_position_default: current_user.notify_on_new_position_default,
          notify_on_support_change_default: current_user.notify_on_support_change_default,
          notify_on_summary_change_default: current_user.notify_on_summary_change_default
        }
      end

      def organization_defaults_params
        params.permit(
          :org_position_cadence_default,
          :notify_on_new_position_default,
          :notify_on_support_change_default,
          :notify_on_summary_change_default
        )
      end
    end
  end
end
