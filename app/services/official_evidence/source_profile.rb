# frozen_string_literal: true

require "uri"

class OfficialEvidence
  # @lat: [[official-service-evidence#Capability is explicit]]
  class SourceProfile
    def self.trusted?(profile)
      return false unless profile.is_a?(Hash)
      profile = profile.deep_symbolize_keys
      return false unless profile[:capability].to_s == "supported"
      return false if %i[publisher jurisdiction source_url identity_source office_identity records_path fields fact_type].any? { |key| profile[key].blank? }
      return false unless profile[:fact_type].to_s.in?(%w[official_service executive_service])
      return false unless profile[:publisher].is_a?(String) && profile[:jurisdiction].is_a?(String)
      return false unless profile[:identity_source].is_a?(String) && profile[:office_identity].is_a?(String)
      return false unless profile[:records_path].is_a?(String) && profile[:fields].is_a?(Hash)

      uri = URI.parse(profile[:source_url].to_s)
      return false unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.query.blank? && uri.userinfo.blank?
      return false unless uri.host.match?(/\A[a-z0-9.-]+\.(gov|mil)\z/i)
      return false unless profile[:date_semantics]&.deep_stringify_keys == {"start" => "inclusive", "end" => "exclusive"}

      return false unless profile[:publisher].casecmp?(uri.host)

      fields = profile[:fields].deep_symbolize_keys
      required = %i[id office_identity title start_date end_date presence]
      return false unless required.all? { |key| fields[key].is_a?(String) && fields[key].present? }
      return false unless fields.values.all? { |path| path.is_a?(String) && path.present? }
      return false unless profile[:date_semantics].is_a?(Hash)

      profile[:date_semantics].deep_stringify_keys == {"start" => "inclusive", "end" => "exclusive"}
    rescue URI::InvalidURIError, NoMethodError, TypeError
      false
    end
  end
end
