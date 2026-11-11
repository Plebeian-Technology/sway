# frozen_string_literal: true

class LegislatorTerm
  # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars#Who says when a term began or ended is recorded, not flattened]]
  module DateSource
    PUBLISHED = "published"

    OBSERVED = "observed"

    ALL = [PUBLISHED, OBSERVED].freeze
  end
end
