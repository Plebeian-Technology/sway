# frozen_string_literal: true

module Api
  module V1
    # @lat: [[bootstrap-caching-and-rate-limiting#Why show is a single request]]
    class BootstrapController < BaseController
      # @lat: [[bootstrap-caching-and-rate-limiting#Why the rate limit exists]]
      rate_limit to: 60, within: 1.minute,
        by: -> { request.remote_ip },
        if: -> { RateLimitConfig.enabled?(:bootstrap) },
        with: -> { render_error(code: "rate_limited", message: "Too many bootstrap requests", status: :too_many_requests) },
        store: ApplicationController::RATE_LIMIT_STORE

      def public_endpoint?
        true
      end

      # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
      def self.expire_botm_cache(sway_locale_id)
        Rails.cache.delete("api_v1_bootstrap:botm:#{sway_locale_id}") if sway_locale_id.present?
      end

      def show
        locale = current_sway_locale

        # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
        botm_json = Rails.cache.fetch("api_v1_bootstrap:botm:#{locale&.id}", expires_in: 60) do
          bill = locale ? Bill.of_the_month(sway_locale: locale) : nil
          bill&.to_sway_json
        end

        # @lat: [[bootstrap-caching-and-rate-limiting#Why cached bills are checked for visibility]]
        if botm_json && !Bill.where(sway_locale: locale).exists?(botm_json["id"])
          bill = locale ? Bill.of_the_month(sway_locale: locale) : nil
          botm_json = bill&.to_sway_json
          Rails.cache.write("api_v1_bootstrap:botm:#{locale&.id}", botm_json, expires_in: 60)
        end

        # @lat: [[bootstrap-caching-and-rate-limiting#Why the featured bill vote is merged in after the cache fetch]]
        if botm_json && current_user
          uv = UserVote.find_by(user_id: current_user.id, bill_id: botm_json["id"])
          botm_json = botm_json.merge("user_vote" => uv&.as_json(only: %i[support]))
        end

        # @lat: [[bootstrap-caching-and-rate-limiting#Why the feature flags cache key carries an explicit version segment]]
        empty_flags = {}
        # @type var empty_flags: Hash[Symbol, bool]
        flags = Rails.cache.fetch("api_v1_bootstrap:feature_flags:#{Rails.env}:v1", expires_in: 60) { empty_flags }

        # @lat: [[bootstrap-caching-and-rate-limiting#Why the locale list has its own longer TTL]]
        # @lat: [[request-locale-selection#Anonymous fallback locale lists are filtered to declared locales]]
        sway_locales_json = Rails.cache.fetch("api_v1_bootstrap:sway_locales:v1", expires_in: 300) do
          SwayLocale.declared.map(&:to_sway_json)
        end

        render json: {
          current_user: current_user_payload,
          locale: locale&.to_sway_json,
          sway_locale: locale&.to_sway_json,
          sway_locales: sway_locales_json,
          bill_of_the_month: botm_json,
          feature_flags: flags,
          unread_notification_count: 0,
          min_supported_version: Sway::Settings.mobile.mobile_min_version,
          latest_version: Sway::Settings.mobile.mobile_latest_version
        }
      end

      private

      def current_user_payload
        return nil if current_user.blank?

        # @lat: [[bootstrap-caching-and-rate-limiting#Why the user address has an explicit payload]]
        u = current_user
        u.to_sway_json.merge(address: u.address&.to_sway_json)
      end
    end
  end
end
