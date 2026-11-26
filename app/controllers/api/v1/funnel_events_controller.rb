# frozen_string_literal: true

# @lat: [[registration-funnel-telemetry#Ingestion API and rate limiting]]
module Api
  module V1
    class FunnelEventsController < BaseController
      prepend_before_action :skip_session_cookie_write
      skip_after_action :forbid_storing_a_one_time_secret

      rate_limit to: 60, within: 1.minute,
        name: "funnel_events",
        by: -> { request.remote_ip },
        only: :create,
        with: -> { render_error(code: "rate_limited", message: "Too many requests", status: :too_many_requests) },
        store: ApplicationController::RATE_LIMIT_STORE

      def public_endpoint?
        true
      end

      def create
        raw_step = funnel_event_params[:step]
        step = RegistrationFunnelEvent.normalize_step(raw_step)

        unless RegistrationFunnelEvent.steps.key?(step)
          return render_error(code: "invalid_step", message: "Invalid funnel step: #{raw_step}", status: :unprocessable_content)
        end

        token = valid_visitor_token(funnel_event_params[:visitor_token]) ||
          valid_visitor_token(cookies[:sway_visitor_token]) ||
          SecureRandom.uuid
        cookies.permanent[:sway_visitor_token] = token

        raw_attr_key = funnel_event_params[:attribution_key].presence || cookies[:sway_attribution_key].presence
        attr_key = raw_attr_key.to_s[0, 100].presence

        user = funnel_attribution_user
        bot = RegistrationFunnelEvent.bot_traffic?(user: user, user_agent: request.user_agent)

        event = RegistrationFunnelEvent.create!(
          visitor_token: token,
          attribution_key: attr_key,
          step: step,
          metadata: sanitized_metadata,
          user: user,
          bot: bot,
          created_at: Time.current
        )
        RegistrationFunnelEvent.mark_visitor_human!(token) if user && !bot

        render json: {ok: true, visitor_token: event.visitor_token}, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_error(code: "invalid_event", message: e.message, status: :unprocessable_content)
      end

      private

      def skip_session_cookie_write
        request.session_options[:skip] = true
      end

      VISITOR_TOKEN_FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/

      def valid_visitor_token(raw_token)
        str = raw_token.to_s
        str if str.match?(VISITOR_TOKEN_FORMAT)
      end

      def funnel_event_params
        if params[:funnel_event].is_a?(ActionController::Parameters) || params[:funnel_event].is_a?(Hash)
          params.require(:funnel_event).permit(:step, :visitor_token, :attribution_key, metadata: {})
        else
          params.permit(:step, :visitor_token, :attribution_key, metadata: {})
        end
      end

      FORBIDDEN_METADATA_KEYS = %w[
        phone
        phone_number
        street
        street_address
        address
        address_line1
        address_line2
        code
        verification_code
        email
        full_name
        name
        password
      ].freeze

      def sanitized_metadata
        raw = params.dig(:funnel_event, :metadata) || params[:metadata]
        return {} unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

        hash = (raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw.to_h).with_indifferent_access
        clean = hash.except(*FORBIDDEN_METADATA_KEYS)
        clean.slice(*clean.keys.first(20)).transform_values do |val|
          if val.is_a?(String)
            val.truncate(200)
          elsif val.is_a?(Numeric) || val.is_a?(TrueClass) || val.is_a?(FalseClass)
            val
          end
        end.compact
      end

      def funnel_attribution_user
        return @current_user if defined?(@current_user)

        @current_user =
          if token_credential_supplied?
            authenticate_with_api_key
          elsif session[:user_id].present?
            u = User.find_by(id: session[:user_id])
            u if u && BrowserSession.current?(session, u)
          end
      end
    end
  end
end
