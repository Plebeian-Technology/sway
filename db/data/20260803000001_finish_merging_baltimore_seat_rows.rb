# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
class FinishMergingBaltimoreSeatRows < ActiveRecord::Migration[8.1]
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
      class_name: "FinishMergingBaltimoreSeatRows::MigrationSwayLocale",
      optional: true
  end

  class MigrationLegislatorTerm < ActiveRecord::Base
    self.table_name = "legislator_terms"

    belongs_to :district,
      class_name: "FinishMergingBaltimoreSeatRows::MigrationDistrict",
      optional: true

    def sway_locale
      district&.sway_locale
    end
  end

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"

    belongs_to :sway_locale,
      class_name: "FinishMergingBaltimoreSeatRows::MigrationSwayLocale",
      optional: true
    has_many :legislator_terms,
      class_name: "FinishMergingBaltimoreSeatRows::MigrationLegislatorTerm",
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

    seat_rows.each do |seat_row|
      keeper = row_holding_the_history_for(seat_row)

      if keeper.nil? || holds_history?(seat_row)
        left_alone += 1
        next
      end

      seat_key = seat_row.external_id
      carry_title_over(seat_row, keeper)
      settle_user_links(seat_row, keeper)
      delete_row(seat_row)
      keeper.update_columns(external_id: seat_key)
      merged += 1
    end

    say("merged #{merged} seats onto the row holding their history; " \
        "left #{left_alone} alone for a person to look at")
  end

  # The rows this deletes held no history, so there is nothing to give back.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Rows named after a seat rather than a person. That is what the seeder writes
  # now, and on production those are the rows holding nothing worth keeping.
  def seat_rows
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

  # The other row for the same person that holds this seat's real record.
  #
  # Matched on the name AND on that row being in office right now. The name alone
  # reaches back to whoever held the seat before, and that is a different person
  # with their own votes. Returns nil unless exactly one row answers, so an
  # unclear seat is left for a person to settle.
  def row_holding_the_history_for(seat_row)
    candidates =
      baltimore_legislators.select { |other|
        other.id != seat_row.id &&
          full_name(other) == full_name(seat_row) &&
          !seat_key?(other.external_id) &&
          other.active_term.present?
      }

    candidates.one? ? candidates.first : nil
  end

  def full_name(legislator)
    "#{legislator.first_name} #{legislator.last_name}".strip.downcase
  end

  # Asks what cannot be rebuilt, which is where 20260801000001 went wrong by
  # asking what merely exists. Score rows are left out on purpose: a score row is
  # a count of votes, and a row with no votes counts to zero from any starting
  # point. User links are left out too — settle_user_links below keeps every one
  # of them.
  def holds_history?(legislator)
    MigrationLegislatorVote.where(legislator_id: legislator.id).any? ||
      MigrationBillCosponsor.where(legislator_id: legislator.id).any? ||
      MigrationBill.where(legislator_id: legislator.id).any?
  end

  # Leaves every reader with exactly one live link to this person.
  #
  # A reader who links to both rows keeps the keeper's link; the copy is deleted.
  # A reader who links only to the seat row has that link moved across, because
  # deleting it would take a representative off their page. Which of the two it
  # is has to be checked per reader — the reassignment that made these links
  # walks users one at a time and any of them could have failed partway.
  #
  # The term scores go first. They count votes cast in a term this migration is
  # about to delete, and they hold the link they belong to in place until they
  # are gone.
  def settle_user_links(seat_row, keeper)
    links = MigrationUserLegislator.where(legislator_id: seat_row.id).to_a
    return if links.empty?

    MigrationUserLegislatorTermScore.where(user_legislator_id: links.map(&:id)).delete_all

    users_already_on_keeper = MigrationUserLegislator.where(legislator_id: keeper.id).pluck(:user_id)
    copies, only_link = links.partition { |link| users_already_on_keeper.include?(link.user_id) }

    switch_keeper_link_on(keeper, copies)
    MigrationUserLegislator.where(id: copies.map(&:id)).delete_all
    MigrationUserLegislator
      .where(id: only_link.map(&:id))
      .update_all(legislator_id: keeper.id, updated_at: Time.current)
  end

  # If the copy was the live link and the keeper's was switched off, deleting the
  # copy would leave that reader with a representative they cannot see. Switch the
  # keeper's link back on first.
  def switch_keeper_link_on(keeper, copies)
    live_user_ids = copies.select(&:active).map(&:user_id)
    return if live_user_ids.empty?

    MigrationUserLegislator
      .where(legislator_id: keeper.id, user_id: live_user_ids, active: false)
      .update_all(active: true, updated_at: Time.current)
  end

  # A term's title is the one field the seeder never writes twice, so it has to
  # come across by hand. A title already on the keeper is left as it is.
  def carry_title_over(seat_row, keeper)
    title = seat_row.active_term&.title
    keeper_term = keeper.active_term
    return if title.blank? || keeper_term.nil? || keeper_term.title.present?

    keeper_term.update_columns(title: title)
  end

  # @lat: [[legislator-photo-orphan-cleanup#Orphan photo cleanup and merge deletion]]
  def delete_row(legislator)
    term_ids = MigrationLegislatorTerm.where(legislator_id: legislator.id).pluck(:id)

    MigrationLegislatorDistrictScore.where(legislator_term_id: term_ids).delete_all
    MigrationLegislatorLocaleScore.where(legislator_term_id: term_ids).delete_all
    MigrationUserLegislatorTermScore.where(legislator_term_id: term_ids).delete_all
    MigrationLegislatorTerm.where(id: term_ids).delete_all
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
