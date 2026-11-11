# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
class CorrectWrongSeatCongressTerms < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
    alias_attribute :state, :region_name if column_names.include?("region_name")
  end

  class MigrationDistrict < ActiveRecord::Base
    self.table_name = "districts"

    belongs_to :sway_locale,
      class_name: "CorrectWrongSeatCongressTerms::MigrationSwayLocale",
      optional: true
  end

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"
  end

  class MigrationLegislatorTerm < ActiveRecord::Base
    self.table_name = "legislator_terms"
  end

  # [bioguide, term start year, seat stored today, seat the history proves]
  CORRECTIONS = [
    ["H001091", 2021, "IA2", "IA1"],
    ["R000608", 2017, "NV0", "NV3"],
    ["C001114", 2023, "UT0", "UT3"],
    ["S001150", 2023, "CA0", "CA30"]
  ].freeze

  def up
    locale = MigrationSwayLocale.find_by(city: "congress", state: "congress")
    if locale.nil?
      say("no congress locale in this database; nothing to do")
      return
    end

    CORRECTIONS.each do |bioguide, start_year, wrong_seat, right_seat|
      correct_one(locale, bioguide, start_year, wrong_seat, right_seat)
    end
  end

  # There is nothing to go back to: the stored seat was the defect.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Repoints one term, matching on the wrong seat as well as the year so a row
  # somebody already fixed — or a database seeded correctly from the start —
  # is left alone. The same person's OTHER terms in the once-wrong seat are
  # safe too: Curtis really does hold UT0 now, but that term starts in 2025,
  # and 2025 is in no correction row.
  def correct_one(locale, bioguide, start_year, wrong_seat, right_seat)
    legislator = MigrationLegislator.find_by(external_id: bioguide, sway_locale_id: locale.id)
    if legislator.nil?
      say("#{bioguide}: not in this database; nothing to do")
      return
    end

    wrong = MigrationDistrict.find_by(name: wrong_seat, sway_locale_id: locale.id)
    term = wrong && MigrationLegislatorTerm.find_by(
      legislator_id: legislator.id, term_start_year: start_year, district_id: wrong.id
    )
    if term.nil?
      say("#{bioguide} #{start_year}: no term filed under #{wrong_seat}; already correct or absent")
      return
    end

    right = MigrationDistrict.find_or_create_by!(name: right_seat, sway_locale: locale)
    term.update_columns(district_id: right.id)
    say("#{bioguide} #{start_year}: seat corrected #{wrong_seat} -> #{right_seat}")
  end
end
