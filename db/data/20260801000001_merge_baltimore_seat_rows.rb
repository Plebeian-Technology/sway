# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
class MergeBaltimoreSeatRows < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
    alias_attribute :state, :region_name if column_names.include?("region_name")

    # @lat: [[migrations-name-no-model#The calculators a stand-in cannot replace]]
    def declared_term_rules?
      SwayLocale::TermRulesRegistry.declared?(name)
    end

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

  class MigrationDistrict < ActiveRecord::Base
    self.table_name = "districts"

    belongs_to :sway_locale,
      class_name: "MergeBaltimoreSeatRows::MigrationSwayLocale",
      optional: true
  end

  class MigrationLegislatorTerm < ActiveRecord::Base
    self.table_name = "legislator_terms"

    belongs_to :district,
      class_name: "MergeBaltimoreSeatRows::MigrationDistrict",
      optional: true

    def sway_locale
      district&.sway_locale
    end
  end

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"

    belongs_to :sway_locale,
      class_name: "MergeBaltimoreSeatRows::MigrationSwayLocale",
      optional: true
    has_many :legislator_terms,
      class_name: "MergeBaltimoreSeatRows::MigrationLegislatorTerm",
      foreign_key: :legislator_id

    # The term running today, from the same window calculator the application uses.
    def active_term
      answerable = legislator_terms.select { |term| term.sway_locale&.declared_term_rules? }
      TermWindow.running_on(Date.current, answerable)
    end
  end

  class MigrationLegislatorVote < ActiveRecord::Base
    self.table_name = "legislator_votes"
  end

  class MigrationBill < ActiveRecord::Base
    self.table_name = "bills"
  end

  class MigrationBillCosponsor < ActiveRecord::Base
    self.table_name = "bill_cosponsors"
  end

  class MigrationUserLegislator < ActiveRecord::Base
    self.table_name = "user_legislators"
  end

  class MigrationUserLegislatorTermScore < ActiveRecord::Base
    self.table_name = "user_legislator_term_scores"
  end

  class MigrationLegislatorDistrictScore < ActiveRecord::Base
    self.table_name = "legislator_district_scores"
  end

  class MigrationLegislatorLocaleScore < ActiveRecord::Base
    self.table_name = "legislator_locale_scores"
  end

  def up
    merged = 0
    left_alone = 0

    empty_seat_rows.each do |empty_row|
      keeper = row_holding_the_data_for(empty_row)

      if keeper.nil? || !carries_nothing?(empty_row)
        left_alone += 1
        next
      end

      seat_key = empty_row.external_id
      carry_title_over(empty_row, keeper)
      delete_row(empty_row)
      keeper.update_columns(external_id: seat_key)
      merged += 1
    end

    say("merged #{merged} seats onto the row holding their history; " \
        "left #{left_alone} alone for a person to look at")
  end

  # The rows this deletes held nothing, so there is nothing to give back.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Rows already named after a seat. Those are the ones the seeder makes now, and
  # in production they are the ones holding nothing.
  def empty_seat_rows
    baltimore_legislators.select { |legislator| seat_key?(legislator.external_id) }
  end

  def seat_key?(external_id)
    external_id.to_s.start_with?(LegislatorsCache::BaltimoreSeatKeys::DISTRICT_SEAT_PREFIX) ||
      [
        LegislatorsCache::BaltimoreSeatKeys::MAYOR_EXTERNAL_ID,
        LegislatorsCache::BaltimoreSeatKeys::COUNCIL_PRESIDENT_EXTERNAL_ID,
        LegislatorsCache::BaltimoreSeatKeys::COMPTROLLER_EXTERNAL_ID
      ].include?(external_id)
  end

  # The other row for the same human that is holding this seat's real history.
  #
  # Matched on the person's name AND on both rows being in office right now.
  # Name alone would reach back to whoever held the seat before, and a seat's
  # previous holder is a different person with their own votes. Requiring both to
  # be serving is what keeps this to the pair that genuinely overlap. Returns nil
  # unless exactly one row answers, so an unclear case is left for a person.
  def row_holding_the_data_for(empty_row)
    candidates =
      baltimore_legislators.select { |other|
        other.id != empty_row.id &&
          full_name(other) == full_name(empty_row) &&
          !seat_key?(other.external_id) &&
          other.active_term.present?
      }

    candidates.one? ? candidates.first : nil
  end

  def full_name(legislator)
    "#{legislator.first_name} #{legislator.last_name}".strip.downcase
  end

  # Proves the row really is empty before anything is deleted. Checked here
  # rather than trusted, because this runs on a database nobody has looked at.
  def carries_nothing?(legislator)
    term_ids = legislator.legislator_terms.pluck(:id)

    MigrationLegislatorVote.where(legislator_id: legislator.id).none? &&
      MigrationUserLegislator.where(legislator_id: legislator.id).none? &&
      MigrationBillCosponsor.where(legislator_id: legislator.id).none? &&
      MigrationBill.where(legislator_id: legislator.id).none? &&
      MigrationLegislatorDistrictScore.where(legislator_term_id: term_ids).none? &&
      MigrationLegislatorLocaleScore.where(legislator_term_id: term_ids).none? &&
      MigrationUserLegislatorTermScore.where(legislator_term_id: term_ids).none?
  end

  # A term's title is the one field the seeder never writes twice, so it has to
  # come across by hand. A title already on the keeper is left as it is.
  def carry_title_over(empty_row, keeper)
    title = empty_row.active_term&.title
    keeper_term = keeper.active_term
    return if title.blank? || keeper_term.nil? || keeper_term.title.present?

    keeper_term.update_columns(title: title)
  end

  # @lat: [[legislator-photo-orphan-cleanup#Orphan photo cleanup and merge deletion]]
  def delete_row(legislator)
    MigrationLegislatorTerm.where(legislator_id: legislator.id).delete_all
    # @lat: [[legislator-photo-orphan-cleanup#Orphan photo cleanup and merge deletion]]
    LegislatorPhotoPurger.purge_for_ids([legislator.id], owner_state: :present)
    MigrationLegislator.where(id: legislator.id).delete_all
  end

  def baltimore_legislators
    region_col = MigrationSwayLocale.column_names.include?("region_name") ? :region_name : :state
    @baltimore_legislators ||=
      MigrationLegislator
        .joins(:sway_locale)
        .where(sway_locales: {city: "baltimore", country: "united_states"}.merge(region_col => "maryland"))
        .includes(legislator_terms: {district: :sway_locale})
        .to_a
  end
end
