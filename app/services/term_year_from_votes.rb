# frozen_string_literal: true

# @lat: [[term-year-from-votes-design#What spec/data/correct_term_years_from_votes_spec.rb's fixtures rebuild]]
class TermYearFromVotes
  def initialize(legislator)
    @legislator = legislator
  end

  def call
    years = cycle_years
    return nil unless years.one?

    year = years.first
    return nil unless voted_while_this_row_existed?(year)

    year
  end

  private

  attr_reader :legislator

  def sway_locale
    @sway_locale ||= legislator.sway_locale
  end

  # @lat: [[term-year-from-votes-design#What spec/data/correct_term_years_from_votes_spec.rb's fixtures rebuild]]
  def cycle_years
    vote_dates.map { |date| TermWindow.cycle_start_year(sway_locale, date) }.uniq
  end

  # @lat: [[term-year-from-votes-design#What spec/data/correct_term_years_from_votes_spec.rb's fixtures rebuild]]
  def voted_while_this_row_existed?(cycle_start_year)
    created_on = legislator.created_at&.to_date
    return true if created_on.nil?

    TermWindow.cycle_ends_on(sway_locale, cycle_start_year) > created_on
  end

  def vote_dates
    legislator
      .legislator_votes
      .includes(:bill)
      .filter_map { |legislator_vote| legislator_vote.bill&.vote_date_time_utc }
  end
end
