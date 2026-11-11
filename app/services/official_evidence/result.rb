# frozen_string_literal: true

class OfficialEvidence
  # @lat: [[official-service-evidence#Capability is explicit]]
  class Result
    attr_reader :facts, :coverage_gaps, :unsupported_reason

    def initialize(facts: [], coverage_gaps: [], unsupported: false, unsupported_reason: nil)
      @facts = facts.freeze
      @coverage_gaps = coverage_gaps.freeze
      @unsupported = unsupported
      @unsupported_reason = unsupported_reason
      freeze
    end

    def unsupported?
      @unsupported
    end

    def supported?
      !unsupported?
    end
  end
end
