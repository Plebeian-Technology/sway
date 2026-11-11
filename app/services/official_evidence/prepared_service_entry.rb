# frozen_string_literal: true

class OfficialEvidence
  # @lat: [[official-service-evidence#Civic writes use the existing term path]]
  class PreparedServiceEntry
    attr_reader :official_fact, :official_service_result, :district

    def initialize(official_fact:, official_service_result:, district:)
      raise ArgumentError, "Official service fact is unsupported" unless official_fact.supported_service?

      @official_fact = official_fact
      @official_service_result = official_service_result
      @district = district
    end

    def self.from_fact(fact:, result:, district:)
      new(official_fact: fact, official_service_result: result, district:)
    end

    def identity
      official_fact.person_identity || raise(ArgumentError, "Supported official service fact has no person identity")
    end

    def external_id
      identity.to_s
    end

    delegate :first_name, to: :official_fact

    delegate :last_name, to: :official_fact

    delegate :party, to: :official_fact

    delegate :title, to: :official_fact

    delegate :chamber, to: :official_fact

    def term_start_year
      began_on.year
    end

    def term_end_year
      ended_on.year
    end

    def began_on
      official_fact.start_date || raise(ArgumentError, "Supported official service fact has no start date")
    end

    def ended_on
      official_fact.end_date || raise(ArgumentError, "Supported official service fact has no end date")
    end

    def proven_terms
      [{
        term_start_year: term_start_year,
        term_end_year: term_end_year,
        title: title,
        district: district,
        chamber: chamber,
        began_on: began_on,
        ended_on: ended_on
      }]
    end

    def current_member?(on: Date.current)
      official_fact.current_member?(on:)
    end

    def terms_from_history?
      false
    end

    def executive?
      false
    end
  end
end
