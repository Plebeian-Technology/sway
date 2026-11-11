# frozen_string_literal: true

require "json"

module Legislation
  # @lat: [[hearing-attachment-discovery-internals#Legislation::BillMetadata.matter_id's own validation]]
  module BillMetadata
    def self.matter_id(external_id, sway_locale:)
      segment = Legislation::Paths.external_id_segment(external_id)
      return nil if segment.nil?

      sway_locale_segment = Legislation::Paths.sway_locale_segment(sway_locale)
      return nil if sway_locale_segment.nil?

      path = Legislation::Paths.bill_metadata_file(segment, sway_locale: sway_locale_segment)
      return nil unless path.exist?

      parsed = JSON.parse(path.read)
      return nil unless parsed.is_a?(Hash)

      matter_id = parsed["matter_id"]

      # @lat: [[hearing-attachment-discovery-internals#Legislation::BillMetadata.matter_id's own validation]]
      case matter_id
      when ::Integer
        matter_id if matter_id.positive? && matter_id <= Legistar::Client::ID_MAX
      when ::String
        return nil unless matter_id.match?(/\A\d{1,10}\z/)

        coerced = Integer(matter_id, 10)
        matter_id if coerced.positive? && coerced <= Legistar::Client::ID_MAX
      end
    rescue JSON::ParserError, SystemCallError, IOError
      # @lat: [[hearing-attachment-discovery-internals#Legislation::BillMetadata.matter_id's own validation]]
      nil
    end
  end
end
