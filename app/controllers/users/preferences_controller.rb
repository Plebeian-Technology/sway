# frozen_string_literal: true

module Users
  # @lat: [[preferences-controller-notes#Why update is rate-limited despite skipping authentication]]
  # @lat: [[preferences-controller-notes#Why theme_id has no DB column, and why validation failures re-render a different page]]
  class PreferencesController < ApplicationController
    # @lat: [[preferences-controller-notes#Why update is rate-limited despite skipping authentication]]
    rate_limit to: 30, within: 1.minute,
      by: -> { request.remote_ip },
      only: :update,
      if: -> { RateLimitConfig.enabled?(:preferences) },
      with: -> { render_rate_limited },
      store: ApplicationController::RATE_LIMIT_STORE

    # @lat: [[theme-mode-and-theme-id-resolution#Why update skips the auth gate]]
    skip_before_action :authenticate_sway_user!, only: :update

    def update
      mode = preference_params[:theme_mode].to_s
      theme_id_value = preference_params[:theme_id].to_s

      # @lat: [[preferences-controller-notes#Why a theme_id-only PATCH skips the User.update call entirely]]
      if current_user
        if mode.present? && !current_user.update(preference_params.except(:theme_id))
          return render_preference_errors(current_user.errors)
        end
      elsif mode.present? && !ThemeHelper::VALID_PREFERENCES.include?(mode)
        # @lat: [[preferences-controller-notes#Why each guard checks .present? rather than re-validating]]
        return render_preference_errors_from_message(
          "Theme mode is not included in the list",
          status: :unprocessable_content,
          code: "validation_failed"
        )
      end

      # @lat: [[preferences-controller-notes#Why each guard checks .present? rather than re-validating]]
      if theme_id_value.present? && !ThemeHelper::VALID_THEME_IDS.include?(theme_id_value)
        return render_preference_errors_from_message(
          "Theme id is not included in the list",
          status: :unprocessable_content,
          code: "validation_failed"
        )
      end

      # @lat: [[preferences-controller-notes#Why each guard checks .present? rather than re-validating]]
      if mode.present?
        cookies.signed[ThemeHelper::COOKIE_NAME] = {
          value: mode,
          expires: 1.year.from_now,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax
        }
      end

      # @lat: [[preferences-controller-notes#Why each guard checks .present? rather than re-validating]]
      if theme_id_value.present?
        cookies.signed[ThemeHelper::THEME_ID_COOKIE_NAME] = {
          value: theme_id_value,
          expires: 1.year.from_now,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax
        }
      end

      # @lat: [[theme-mode-and-theme-id-resolution#Why a successful update uses redirect_back, not a fixed path]]
      if mobile_api_request?
        render json: {redirect: "/profile", flash: "Preferences updated"}
      else
        redirect_back_or_to("/profile", notice: "Preferences updated")
      end
    rescue ActionController::ParameterMissing => e
      render_preference_errors_from_message(e.message, status: :bad_request, code: "bad_request")
    end

    private

    def preference_params
      params.require(:preferences).permit(:theme_mode, :theme_id)
    end

    def render_preference_errors(errors)
      if mobile_api_request?
        render json: {
          error: {
            code: "validation_failed",
            message: "Preferences invalid",
            details: errors.as_json
          }
        }, status: :unprocessable_content
      else
        # @lat: [[theme-mode-and-theme-id-resolution#Why validation failures redirect back with an Inertia errors prop, not a plain redirect]]
        redirect_back_or_to("/bills",
          inertia: {errors: {preferences: errors.full_messages.join(", ").presence || "Preferences invalid"}})
      end
    end

    def render_preference_errors_from_message(message, status:, code:)
      if mobile_api_request?
        # @lat: [[render-error-nonnil-fields-workaround#Why some call sites delegate to JsonErrorRenderable instead of hand-building the envelope]]
        render_error(code: code, message: message, status: status)
      else
        # @lat: [[theme-mode-and-theme-id-resolution#Why validation failures redirect back with an Inertia errors prop, not a plain redirect]]
        redirect_back_or_to("/bills", inertia: {errors: {preferences: message}})
      end
    end
  end
end
