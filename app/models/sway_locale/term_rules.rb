# frozen_string_literal: true

class SwayLocale
  # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
  class TermRules
    # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
    class Undeclared < StandardError; end

    attr_reader :convening

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
    attr_reader :cycle_anchor_year, :cycle_years

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster evidence for observed departures]]
    attr_reader :roster_lists_only_current_legislators

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster evidence for observed departures]]
    attr_reader :publishes_term_history

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
    attr_reader :publishes_exact_term_dates

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
    attr_reader :identified_by

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Configured office metadata for current seat-keyed rosters]]
    attr_reader :seat_chambers

    def initialize(
      convening:,
      cycle_anchor_year:,
      cycle_years:,
      roster_lists_only_current_legislators:,
      publishes_term_history:,
      publishes_exact_term_dates:,
      identified_by:,
      seat_chambers: {}
    )
      @convening = convening
      @cycle_anchor_year = cycle_anchor_year
      @cycle_years = cycle_years
      @roster_lists_only_current_legislators = roster_lists_only_current_legislators
      @publishes_term_history = publishes_term_history
      @publishes_exact_term_dates = publishes_exact_term_dates
      @identified_by = identified_by
      @seat_chambers = seat_chambers.to_h do |title, chamber|
        [title.to_s.dup.freeze, chamber.to_s.dup.freeze]
      end.freeze
    end
  end
end
