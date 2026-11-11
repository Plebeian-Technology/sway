# frozen_string_literal: true

require "erb"

# @lat: [[external-asset-mirroring-design#MirroredAssetUrl]]
class MirroredAssetUrl
  class << self
    def for(attachment, fallback:)
      # @lat: [[external-asset-mirroring-design#MirroredAssetUrl]]
      return external_fallback_url(fallback) if attachment.nil?
      return external_fallback_url(fallback) unless attachment.attached?

      Rails.application.routes.url_helpers.rails_storage_proxy_url(attachment, **url_options)
    rescue => e
      SwayLogging.warn("MirroredAssetUrl.for failed error=#{e.class}: #{e.message}")
      external_fallback_url(fallback)
    end

    private

    # @lat: [[external-asset-mirroring-design#MirroredAssetUrl#Why a bare bucket key falls back to a constructed bucket URL]]
    def external_fallback_url(fallback)
      return fallback if fallback.blank?

      trimmed = fallback.to_s.strip
      return trimmed if trimmed.start_with?("/") && !trimmed.start_with?("//")
      return trimmed if trimmed.match?(%r{\Ahttps?://}i)
      return nil if trimmed.match?(%r{\A[a-zA-Z][a-zA-Z\d+.-]*:})

      escaped_name = trimmed.split("/").map { |segment| ERB::Util.url_encode(segment) }.join("/")
      "https://storage.googleapis.com/#{SwayGoogleCloudStorage::BUCKETS[:ASSETS]}/#{escaped_name}"
    end

    # @lat: [[external-asset-mirroring-design#MirroredAssetUrl#Why route options win over mailer options]]
    def url_options
      mailer_options = Rails.application.config.action_mailer.default_url_options || {}
      route_options = Rails.application.routes.default_url_options || {}

      mailer_options.merge(route_options)
    end
  end
end
