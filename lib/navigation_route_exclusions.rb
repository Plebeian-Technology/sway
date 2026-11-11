# frozen_string_literal: true

require "uri"

# @lat: [[query-parameter-navigation-carry#Excluded route constants and security boundaries]]
module NavigationRouteExclusions
  EXCLUDED_PREFIXES = [
    "/api/v1",
    "/api",
    "/sessions",
    "/test/sessions",
    "/passkeys",
    "/registrations",
    "/phone_verification",
    "/sway_registration",
    "/users/webauthn",
    "/users/passkeys"
  ].freeze

  def self.excluded_path?(path_or_url)
    return false if path_or_url.blank?

    pathname = normalize_path(path_or_url)
    return false if pathname.empty?

    EXCLUDED_PREFIXES.any? do |prefix|
      normalized_prefix = (prefix.end_with?("/") && prefix.length > 1) ? prefix.sub(%r{/+\z}, "") : prefix
      pathname == normalized_prefix || pathname.start_with?("#{normalized_prefix}/")
    end
  end

  def self.normalize_path(path_or_url)
    str = path_or_url.to_s.strip
    return "" if str.empty?

    str = str.split("#", 2).first || ""
    str = str.split("?", 2).first || ""
    return "" if str.empty?

    if str.include?("://")
      begin
        uri = URI.parse(str)
        str = uri.path.to_s
      rescue URI::InvalidURIError
        slash_idx = str.index("/", str.index("://") + 3)
        str = slash_idx ? str[slash_idx..] : "/"
      end
    end

    str = "/#{str}" unless str.start_with?("/")
    str = str.sub(%r{/+\z}, "") if str.length > 1
    str
  end
end
