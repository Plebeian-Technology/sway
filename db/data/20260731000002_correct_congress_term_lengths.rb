# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
class CorrectCongressTermLengths < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
    alias_attribute :state, :region_name if column_names.include?("region_name")

    def congress?
      city_name == "congress" && region_name == "congress"
    end

    # @lat: [[migrations-name-no-model#The calculators a stand-in cannot replace]]
    def term_rules
      SwayLocale::TermRulesRegistry.fetch(name)
    end

    def jurisdiction_rules
      SwayLocale::JurisdictionRulesRegistry.fetch(name)
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

  class MigrationDistrict < ActiveRecord::Base
    self.table_name = "districts"

    belongs_to :sway_locale,
      class_name: "CorrectCongressTermLengths::MigrationSwayLocale",
      optional: true
  end

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"
  end

  class MigrationLegislatorTerm < ActiveRecord::Base
    self.table_name = "legislator_terms"

    belongs_to :legislator,
      class_name: "CorrectCongressTermLengths::MigrationLegislator",
      optional: true
    belongs_to :district,
      class_name: "CorrectCongressTermLengths::MigrationDistrict",
      optional: true

    def sway_locale
      district&.sway_locale
    end
  end

  def up
    roster = CongressRoster.new
    corrected_spans = 0
    filled_titles = 0
    left_alone = 0

    MigrationLegislatorTerm.includes(:legislator, district: :sway_locale).find_each do |term|
      next unless term.sway_locale&.congress?

      title = roster.title_in(term.legislator.external_id, term.term_start_year)
      if title.nil? || title == CongressChamber::PRESIDENT
        left_alone += 1
        next
      end

      changes = changes_for(term, title, roster)
      next if changes.empty?

      corrected_spans += 1 if changes.key?(:term_end_year)
      filled_titles += 1 if changes.key?(:title)
      term.update_columns(changes)
    end

    say("corrected #{corrected_spans} term spans and #{filled_titles} titles; " \
        "left #{left_alone} terms alone — the roster holds only sitting members")
  end

  # The spans this replaces were wrong, so there is nothing to restore.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def changes_for(term, title, roster)
    changes = {}
    changes[:title] = title if term.title != title

    wanted_end = end_year_for(term, title, roster)
    changes[:term_end_year] = wanted_end if term.term_end_year != wanted_end
    changes
  end

  # A term runs the length its chamber sets, but never past the day the member
  # stopped serving in that chamber — somebody who moved from the House to the
  # Senate mid-decade did not finish the House term they were in.
  def end_year_for(term, title, roster)
    full_length = term.term_start_year + CongressChamber.term_years_for(title)
    service_ended = roster.service_ended_in(term.legislator.external_id, term.term_start_year)
    return full_length if service_ended.nil? || service_ended <= term.term_start_year

    [full_length, service_ended].min
  end
end
