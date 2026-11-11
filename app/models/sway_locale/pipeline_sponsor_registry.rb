# frozen_string_literal: true

class SwayLocale
  # @lat: [[legislation-ingestion#Declared fallback associations]]
  module PipelineSponsorRegistry
    DECLARATIONS = {
      "baltimore-maryland-united_states" => {
        "council" => {role: "Council President", term_title: "Council President", external_id: nil}.freeze
      }.freeze,
      "maryland-maryland-united_states" => {
        "house" => {
          role: "Speaker of the House",
          term_title: "Delegate",
          external_id: "ocd-person/366c0122-84a8-460e-bc98-93d4ca5f0176"
        }.freeze,
        "senate" => {
          role: "President of the Senate",
          term_title: "Senator",
          external_id: "ocd-person/86f0d40f-05f4-46a2-9c24-21ff52fdc6fe"
        }.freeze
      }.freeze
    }.freeze

    def self.for(locale_name, chamber)
      DECLARATIONS.dig(locale_name, chamber)
    end
  end
end
