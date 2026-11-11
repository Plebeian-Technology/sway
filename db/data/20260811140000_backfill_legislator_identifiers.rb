# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
class BackfillLegislatorIdentifiers < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
    alias_attribute :state, :region_name if column_names.include?("region_name")

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

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"

    belongs_to :sway_locale,
      class_name: "BackfillLegislatorIdentifiers::MigrationSwayLocale",
      optional: true
  end

  class MigrationLegislatorIdentifier < ActiveRecord::Base
    self.table_name = "legislator_identifiers"

    belongs_to :legislator,
      class_name: "BackfillLegislatorIdentifiers::MigrationLegislator",
      optional: true

    def self.record!(legislator:, identity:)
      find_or_create_by!(
        sway_locale_id: legislator.sway_locale_id,
        source: identity.source,
        value: identity.value
      ) { |identifier| identifier.legislator = legislator }
    end
  end

  def up
    recorded = 0
    confirmed = 0
    moved = 0
    left_alone = 0
    collisions = []

    locales_holding_legislators.each do |sway_locale|
      rules = sway_locale.term_rules

      legislators_in(sway_locale).each do |legislator|
        identity = identity_for(legislator, rules.identified_by)

        if identity.nil?
          left_alone += 1
          next
        end

        holder = row_already_identified_as(sway_locale, identity, legislator)
        if holder
          collisions << "#{sway_locale.name} #{identity.value}: rows #{holder.id} and #{legislator.id}"
          left_alone += 1
          next
        end

        # record!, not create!
        already_held = legislator_already_holds(sway_locale, identity, legislator)
        MigrationLegislatorIdentifier.record!(legislator: legislator, identity: identity)
        already_held ? (confirmed += 1) : (recorded += 1)

        next if legislator.external_id == identity.value

        # update_columns, not update! — the same rule every backfill in this
        # directory follows. An after-commit callback here would re-mirror
        # photos and rewrite score rows for every legislator in the database.
        legislator.update_columns(external_id: identity.value)
        moved += 1
      end
    end

    say("recorded #{recorded} new identifiers, confirmed #{confirmed} already held, " \
        "moved #{moved} external_ids, left #{left_alone} rows for a person to look at")
    collisions.each { |collision| say("COLLISION, both rows left alone — #{collision}") }
  end

  # The identifiers are derived, so they can be derived again. The external_ids
  # this moved cannot be put back without knowing which half of each value was
  # the seat, and Baltimore's earlier merges are already irreversible for the
  # same reason.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Only locales that actually hold legislators. A locale registration created
  # for a reader's city has none, and has no roster, so it has no identity
  # scheme to declare yet.
  def locales_holding_legislators
    MigrationSwayLocale.where(id: MigrationLegislator.distinct.select(:sway_locale_id)).to_a
  end

  def legislators_in(sway_locale)
    MigrationLegislator.where(sway_locale_id: sway_locale.id).order(:id).to_a
  end

  # Returns nil when this row is not one the locale's roster can name — a
  # Baltimore row still carrying a person-shaped id from before the seats were
  # keyed, or a seat row whose name reduces to nothing.
  def identity_for(legislator, identified_by)
    case identified_by
    when :person
      LegislatorIdentity.from_published_id(
        published_id_source(legislator.sway_locale),
        legislator.external_id
      )
    when :seat
      if LegislatorIdentity.seat_from(legislator.external_id)
        return LegislatorIdentity.new(
          source: LegislatorIdentity::SEAT_AND_NAME,
          value: legislator.external_id
        )
      end

      return nil unless LegislatorsCache::BaltimoreSeatKeys.seat_key?(legislator.external_id)

      LegislatorIdentity.seat_and_name(
        seat: legislator.external_id,
        first_name: legislator.first_name,
        last_name: legislator.last_name
      )
    else
      raise "SwayLocale #{legislator.sway_locale.name.inspect} declares identified_by " \
            "#{identified_by.inspect}, which this backfill has no rule for"
    end
  end

  # Which source published the person-level id already sitting in external_id.
  def published_id_source(sway_locale)
    case sway_locale.jurisdiction_rules.roster_source
    when :congress_dot_gov then LegislatorIdentity::BIOGUIDE
    when :open_states then LegislatorIdentity::OPENSTATES
    when :curated then LegislatorIdentity::CURATED_PERSON
    else
      raise "SwayLocale #{sway_locale.name.inspect} reads roster_source " \
            "#{sway_locale.jurisdiction_rules.roster_source.inspect}, which this backfill " \
            "has no identifier source name for"
    end
  end

  def row_already_identified_as(sway_locale, identity, legislator)
    MigrationLegislatorIdentifier
      .where(sway_locale_id: sway_locale.id, source: identity.source, value: identity.value)
      .where.not(legislator_id: legislator.id)
      .first
      &.legislator
  end

  def legislator_already_holds(sway_locale, identity, legislator)
    MigrationLegislatorIdentifier.exists?(
      legislator_id: legislator.id,
      sway_locale_id: sway_locale.id,
      source: identity.source,
      value: identity.value
    )
  end
end
