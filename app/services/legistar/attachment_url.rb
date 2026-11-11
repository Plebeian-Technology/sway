# frozen_string_literal: true

require "uri"

module Legistar
  # @lat: [[legistar-attachment-url-allowlist#The host string is never truncated for the match itself]]
  class AttachmentUrl
    # @lat: [[legistar-attachment-url-allowlist#What the allowlist covers, and what it deliberately does not]]
    ALLOWED_HOST = /\A([a-z0-9-]+\.)*legistar1?\.com\z/i

    # @lat: [[legistar-attachment-url-allowlist#Why only port 443 is allowed]]
    ALLOWED_PORT = 443

    # @lat: [[legistar-attachment-url-allowlist#Why every rejection reason is length-capped through one constant]]
    MAX_REASON_LENGTH = 200

    # @lat: [[legistar-attachment-url-allowlist#Why .allowed? is kept even though production never calls it]]
    def self.allowed?(url)
      rejection_reason(url).nil?
    end

    # @lat: [[legistar-attachment-url-allowlist#The host string is never truncated for the match itself]]
    def self.normalize(value)
      # @lat: [[legistar-attachment-url-allowlist#Why .normalize converts to a String before anything else]]
      Sway::Utf8.scrub(value.to_s).strip
    end

    # @lat: [[legistar-attachment-url-allowlist#Why rejection_reason's message names the host but never the path or query]]
    def self.rejection_reason(url)
      return bounded("blocked url: not a string") unless url.is_a?(::String)

      candidate = normalize(url)
      return bounded("blocked url: blank") if candidate.empty?

      uri =
        begin
          URI.parse(candidate)
        rescue URI::Error
          nil
        end
      return bounded("blocked url: unparseable") if uri.nil?

      # @lat: [[legistar-attachment-url-allowlist#The host string is never truncated for the match itself]]
      host = uri.host.to_s.chomp(".")

      # @lat: [[legistar-attachment-url-allowlist#The host string is never truncated for the match itself]]
      display_host = host[0, 100].to_s

      unless uri.is_a?(URI::HTTPS)
        return bounded("blocked url: host=#{display_host} scheme=#{uri.scheme.to_s[0, 20]} (https required)")
      end
      if uri.userinfo.present?
        return bounded("blocked url: host=#{display_host} carries credentials, which are not accepted")
      end
      unless host.match?(ALLOWED_HOST)
        return bounded("blocked url: host=#{display_host} is not an allowed Legistar attachment host")
      end
      if uri.port != ALLOWED_PORT
        return bounded("blocked url: host=#{display_host} port=#{uri.port} (only #{ALLOWED_PORT} is allowed)")
      end

      nil
    end

    def self.bounded(reason)
      reason[0, MAX_REASON_LENGTH].to_s
    end
  end
end
