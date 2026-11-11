# frozen_string_literal: true

require "uri"
require "ipaddr"

module Llm
  # @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Cited local news reporting and domain-restricted web search#Seeded newsrooms and domain filtering]]
  module AllowedDomain
    MAX_ALLOWED_DOMAINS = 64

    VALID_HOST_REGEX = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+\z/i

    def self.from_url(url)
      return nil unless url.is_a?(String)

      trimmed = url.strip
      return nil if trimmed.empty?
      return nil if trimmed.length > 8192

      uri = URI.parse(trimmed)
      return nil unless uri.scheme&.downcase == "https"

      raw_host = uri.host
      return nil if raw_host.blank?

      host = raw_host.downcase.sub(/\Awww\./, "")
      return nil if host.empty?
      return nil unless host.include?(".")

      return nil if ip_address?(host)

      return nil unless host.match?(VALID_HOST_REGEX)
      return nil if host == "localhost" || host.end_with?(".localhost")

      path = uri.path.to_s.sub(%r{/+\z}, "")
      path = "/#{path}" if path.present? && !path.start_with?("/")

      if path.present? && path != "/"
        "#{host}#{path}"
      else
        host
      end
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def self.filter_list(urls)
      return [] unless urls.is_a?(Array)

      converted = urls.filter_map { |u| from_url(u) }.uniq
      if converted.length > MAX_ALLOWED_DOMAINS
        SwayLogging.warn(
          "llm.allowed_domains.truncated",
          max_domains: MAX_ALLOWED_DOMAINS,
          received: converted.length,
          message: "allowed_domains list exceeded API limit of #{MAX_ALLOWED_DOMAINS}; truncated to first #{MAX_ALLOWED_DOMAINS}"
        )
        converted = converted.first(MAX_ALLOWED_DOMAINS)
      end

      converted
    end

    def self.ip_address?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::InvalidAddressError
      false
    end
    private_class_method :ip_address?
  end
end
