# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#Matching a name resolves against the roster of the vote's own day]]
class CorrectTermYearsFromVotes < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
    alias_attribute :state, :region_name if column_names.include?("region_name")

    # @lat: [[migrations-name-no-model#The calculators a stand-in cannot replace]]
    def term_rules
      SwayLocale::TermRulesRegistry.fetch(name)
    end

    def name
      "#{city_name}-#{region_name}-#{country_name}"
    end

    def city_name
      format_name(city)
    end

    def region_name
      format_name(RegionUtil.from_region_code_to_region_name(state))
    end

    def country_name
      format_name(RegionUtil.from_country_code_to_name(country))
    end

    private

    def format_name(value)
      value.to_s.strip.downcase.split(" ").join("_")
    end
  end

  class MigrationBill < ActiveRecord::Base
    self.table_name = "bills"

    # The earlier of the two chamber votes, which is what TermYearFromVotes reads.
    def vote_date_time_utc
      house = house_vote_date_time_utc
      senate = senate_vote_date_time_utc
      return nil unless house || senate
      return house || senate unless house && senate

      house.before?(senate) ? house : senate
    end
  end

  class MigrationLegislatorVote < ActiveRecord::Base
    self.table_name = "legislator_votes"

    belongs_to :bill,
      class_name: "CorrectTermYearsFromVotes::MigrationBill",
      optional: true
  end

  class MigrationLegislatorTerm < ActiveRecord::Base
    self.table_name = "legislator_terms"
  end

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"

    belongs_to :sway_locale,
      class_name: "CorrectTermYearsFromVotes::MigrationSwayLocale",
      optional: true
    has_many :legislator_votes,
      class_name: "CorrectTermYearsFromVotes::MigrationLegislatorVote",
      foreign_key: :legislator_id
    has_many :legislator_terms,
      class_name: "CorrectTermYearsFromVotes::MigrationLegislatorTerm",
      foreign_key: :legislator_id
  end

  def up
    corrected = 0
    left_alone = 0

    MigrationLegislator.includes(:sway_locale, legislator_votes: :bill).find_each do |legislator|
      proven_year = TermYearFromVotes.new(legislator).call

      if proven_year.nil?
        left_alone += 1
        next
      end

      corrected += correct_terms_for(legislator, proven_year)
    end

    say("corrected #{corrected} terms; left #{left_alone} legislators alone for want of evidence")
  end

  # Term years are re-derived from votes, so rolling forward again would just
  # recompute the same answer. There is nothing to restore: the years this
  # replaces were wrong.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # A legislator whose votes all fall in one cycle should hold one term, in that
  # cycle. Only the term that is already closest to the evidence is moved, and
  # only when moving it cannot collide with another term the same legislator
  # already holds — legislator_terms is UNIQUE(legislator_id, term_start_year).
  def correct_terms_for(legislator, proven_year)
    terms = legislator.legislator_terms.to_a
    return 0 unless terms.one?

    term = terms.first
    return 0 if term.term_start_year == proven_year

    term.update_columns(
      term_start_year: proven_year,
      term_end_year: proven_year + years_the_term_runs(term)
    )
    1
  end

  # Slides the term to the proven cycle WITHOUT changing how long it runs.
  #
  # Recomputing the length from the locale would be wrong: it would hand every
  # senator a 2-year term, because Congress seats are 2 years and Senate seats
  # are 6. That mistake is already in the data from the phase 65 backfill and is
  # tracked separately; this migration must not spread it. Keeping the existing
  # length means a 4-year Baltimore term stays 4 years and a 6-year Senate term
  # stays 6.
  def years_the_term_runs(term)
    term.term_end_year - term.term_start_year
  end
end
