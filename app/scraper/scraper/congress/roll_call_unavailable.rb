# frozen_string_literal: true

module Scraper
  module Congress
    # @lat: [[legislator-votes-update-rake-task#Circuit breaker and permanent refusals]]
    class RollCallUnavailable < StandardError
      attr_reader :chamber, :congress, :session, :roll_call_number, :reason

      def initialize(chamber:, congress:, session:, roll_call_number:, reason:)
        @chamber = chamber
        @congress = congress
        @session = session
        @roll_call_number = roll_call_number
        @reason = reason

        super("Roll call unavailable for #{chamber} #{congress}-#{session} ##{roll_call_number}: #{reason}")
      end
    end
  end
end
