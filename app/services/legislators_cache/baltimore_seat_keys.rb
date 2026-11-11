# frozen_string_literal: true

module LegislatorsCache
  # @lat: [[legislators-cache-baltimore-and-openstates-refresh#Why a Baltimore seat's identity is split from the person who fills it]]
  module BaltimoreSeatKeys
    MAYOR_EXTERNAL_ID = "baltimore-mayor"
    COUNCIL_PRESIDENT_EXTERNAL_ID = "baltimore-council-president"
    COMPTROLLER_EXTERNAL_ID = "baltimore-comptroller"

    OFFICE_EXTERNAL_IDS = [
      MAYOR_EXTERNAL_ID,
      COUNCIL_PRESIDENT_EXTERNAL_ID,
      COMPTROLLER_EXTERNAL_ID
    ].freeze

    DISTRICT_SEAT_PREFIX = "baltimore-district-"

    class << self
      def district_seat_external_id(district_number)
        "#{DISTRICT_SEAT_PREFIX}#{district_number}"
      end

      # @lat: [[legislators-cache-baltimore-and-openstates-refresh#Why a Baltimore seat's identity is split from the person who fills it]]
      def seat_key?(key)
        key.to_s.start_with?(DISTRICT_SEAT_PREFIX) || OFFICE_EXTERNAL_IDS.include?(key.to_s)
      end
    end
  end
end
