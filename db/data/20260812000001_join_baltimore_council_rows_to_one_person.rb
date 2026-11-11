# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
class JoinBaltimoreCouncilRowsToOnePerson < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
    alias_attribute :state, :region_name if column_names.include?("region_name")
  end

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"

    belongs_to :sway_locale,
      class_name: "JoinBaltimoreCouncilRowsToOnePerson::MigrationSwayLocale",
      optional: true
  end

  class MigrationLegislatorTerm < ActiveRecord::Base
    self.table_name = "legislator_terms"
  end

  class MigrationLegislatorVote < ActiveRecord::Base
    self.table_name = "legislator_votes"
  end

  class MigrationLegislatorIdentifier < ActiveRecord::Base
    self.table_name = "legislator_identifiers"

    belongs_to :legislator,
      class_name: "JoinBaltimoreCouncilRowsToOnePerson::MigrationLegislator",
      optional: true
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

  # external_id of the row named after the person => the seat they sat for on
  # the 2020-2024 council; SEAT_HELD_NOW below overrides the one person whose
  # office changed.
  SAME_PERSON = {
    "antonio-glover-2020" => "baltimore-district-13",
    "brandon-scott-2020" => "baltimore-mayor",
    "danielle-mccray-2020" => "baltimore-district-2",
    "isaac-schleifer-2020" => "baltimore-district-5",
    "james-torrence-2020" => "baltimore-district-7",
    "john-bullock-2020" => "baltimore-district-9",
    "mark-conway-2020" => "baltimore-district-4",
    "odette-ramos-2020" => "baltimore-district-14",
    "phylicia-porter-2020" => "baltimore-district-10",
    "ryan-dorsey-2020" => "baltimore-district-3",
    "sharon-middleton-2020" => "baltimore-district-6",
    "zeke-cohen-2020" => "baltimore-district-1" # elected Council President in 2024
  }.freeze

  # Cohen's newer row is under the office he holds now, not the seat he sat for.
  SEAT_HELD_NOW = {"zeke-cohen-2020" => "baltimore-council-president"}.freeze

  def up
    joined = 0
    left_alone = []

    SAME_PERSON.each_key do |retiring_key|
      retiring = baltimore_row(retiring_key)
      next if retiring.nil? # already joined, or never in this database

      keeper = keeper_for(retiring, retiring_key)
      if keeper.nil?
        left_alone << "#{retiring_key}: no row for them under #{seat_now(retiring_key)}"
        next
      end

      # Checked BEFORE anything moves. Two rows sharing a term start year would
      # mean the pair is not what this migration was told it is, and finding
      # that out halfway through — on a foreign key, while deleting — would
      # abort the deploy with the work half done.
      clashing = shared_term_start_years(retiring, keeper)
      if clashing.any?
        left_alone << "#{retiring_key}: both rows carry a term starting #{clashing.sort.inspect}"
        next
      end

      MigrationLegislator.transaction do
        move_what_hangs_off(retiring, keeper)
        settle_reader_links(retiring, keeper)
        move_terms(retiring, keeper)
        carry_identifiers_over(retiring, keeper)
        # @lat: [[legislator-photo-orphan-cleanup#Orphan photo cleanup and merge deletion]]
        LegislatorPhotoPurger.purge_for_ids([retiring.id], owner_state: :present)
        MigrationLegislator.where(id: retiring.id).delete_all
      end
      joined += 1
    end

    say("joined #{joined} pairs of rows into one person each")
    left_alone.each { |note| say("LEFT ALONE — #{note}") }
  end

  # The retired rows are deleted. Which votes came from which of the two rows is
  # not recorded anywhere afterwards, so this cannot be undone.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def seat_now(retiring_key)
    SEAT_HELD_NOW.fetch(retiring_key, SAME_PERSON.fetch(retiring_key))
  end

  # The row that holds this person's current term.
  #
  # Found by the identity the seeder itself would build: the seat they hold now,
  # paired with the name on the row being retired. So the two rows have to carry
  # the SAME name to be joined — if the newer roster spells it differently, this
  # finds nothing and says so, which is the safe direction. Two rows left
  # standing is a visible duplicate; a wrong join is a rewritten record.
  def keeper_for(retiring, retiring_key)
    identity = LegislatorIdentity.seat_and_name(
      seat: seat_now(retiring_key),
      first_name: retiring.first_name,
      last_name: retiring.last_name
    )
    return nil if identity.nil?

    MigrationLegislator.find_by(sway_locale_id: retiring.sway_locale_id, external_id: identity.value)
  end

  # update_all rather than update!, the same rule every backfill in this
  # directory follows: an after-commit callback here would re-mirror photos and
  # rewrite score rows for every row it touched.
  def move_what_hangs_off(retiring, keeper)
    MigrationLegislatorVote.where(legislator_id: retiring.id).update_all(legislator_id: keeper.id)
    MigrationBill.where(legislator_id: retiring.id).update_all(legislator_id: keeper.id)
    MigrationBillCosponsor.where(legislator_id: retiring.id).update_all(legislator_id: keeper.id)
  end

  # Leaves every reader with one live link to this person, and keeps the
  # agreement they had recorded under each term.
  #
  # A reader linked to BOTH rows keeps the keeper's link, and the retiring
  # link's term scores are moved onto it before the link goes — they count a
  # term that is about to belong to the keeper. A reader linked only to the
  # retiring row has that link moved across, and its scores come with it
  # untouched.
  def settle_reader_links(retiring, keeper)
    links = MigrationUserLegislator.where(legislator_id: retiring.id).to_a
    return if links.empty?

    already_on_keeper = MigrationUserLegislator.where(legislator_id: keeper.id).index_by(&:user_id)
    duplicates, only_link = links.partition { |link| already_on_keeper.key?(link.user_id) }

    duplicates.each do |duplicate|
      kept = already_on_keeper.fetch(duplicate.user_id)
      carry_term_scores_over(duplicate, kept)
      # If the duplicate was the live one, the reader would lose sight of this
      # person when it goes.
      kept.update_columns(active: true, updated_at: Time.current) if duplicate.active && !kept.active
    end

    MigrationUserLegislator.where(id: duplicates.map(&:id)).delete_all
    MigrationUserLegislator
      .where(id: only_link.map(&:id))
      .update_all(legislator_id: keeper.id, updated_at: Time.current)
  end

  # user_legislator_term_scores is UNIQUE on (user_legislator_id,
  # legislator_term_id). The two links count different terms — that is the whole
  # reason the rows were split — so nothing should collide; a row that would is
  # left where it is rather than overwriting what the keeper already counted.
  def carry_term_scores_over(from_link, to_link)
    already_counted =
      MigrationUserLegislatorTermScore.where(user_legislator_id: to_link.id).pluck(:legislator_term_id)

    MigrationUserLegislatorTermScore
      .where(user_legislator_id: from_link.id)
      .where.not(legislator_term_id: already_counted)
      .update_all(user_legislator_id: to_link.id, updated_at: Time.current)

    MigrationUserLegislatorTermScore.where(user_legislator_id: from_link.id).delete_all
  end

  # legislator_terms is UNIQUE on (legislator_id, term_start_year). The pair is
  # checked for a clash before any of this runs, so every term moves.
  def shared_term_start_years(retiring, keeper)
    MigrationLegislatorTerm.where(legislator_id: retiring.id).pluck(:term_start_year) &
      MigrationLegislatorTerm.where(legislator_id: keeper.id).pluck(:term_start_year)
  end

  # The term keeps its id, so every score row counted under it comes along and
  # is now part of the one person's history.
  def move_terms(retiring, keeper)
    MigrationLegislatorTerm
      .where(legislator_id: retiring.id)
      .update_all(legislator_id: keeper.id, updated_at: Time.current)
  end

  # Keeps the mapping instead of throwing it away, so anything still holding the
  # old name resolves to the person who is left. Any identifier already on the
  # retiring row moves too — it would otherwise hold that row in place on a
  # foreign key when it is deleted.
  def carry_identifiers_over(retiring, keeper)
    held_by_keeper =
      MigrationLegislatorIdentifier.where(legislator_id: keeper.id).pluck(:source, :value)

    MigrationLegislatorIdentifier.where(legislator_id: retiring.id).find_each do |identifier|
      if held_by_keeper.include?([identifier.source, identifier.value])
        identifier.delete
      else
        identifier.update_columns(legislator_id: keeper.id, updated_at: Time.current)
      end
    end

    MigrationLegislatorIdentifier.find_or_create_by!(
      sway_locale_id: keeper.sway_locale_id,
      source: LegislatorIdentity::CURATED_PERSON,
      value: retiring.external_id
    ) { |identifier| identifier.legislator = keeper }
  end

  def baltimore_row(external_id)
    region_col = MigrationSwayLocale.column_names.include?("region_name") ? :region_name : :state
    MigrationLegislator
      .joins(:sway_locale)
      .where(sway_locales: {city: "baltimore", country: "united_states"}.merge(region_col => "maryland"))
      .find_by(external_id: external_id)
  end
end
