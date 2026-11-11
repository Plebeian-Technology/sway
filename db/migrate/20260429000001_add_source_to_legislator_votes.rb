# frozen_string_literal: true

class AddSourceToLegislatorVotes < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"

    def congress?
      city_name == "congress" && region_name == "congress"
    end

    def regional?
      return false if congress?

      RegionUtil.from_region_name_to_region_code(city_name).present? &&
        RegionUtil.from_region_name_to_region_code(city_name) ==
          RegionUtil.from_region_name_to_region_code(region_name)
    end

    def city_name
      format_name(city)
    end

    def region_name
      val = if has_attribute?(:region_name)
        self[:region_name]
      elsif has_attribute?(:state)
        self[:state]
      end
      format_name(RegionUtil.from_region_code_to_region_name(val) || val)
    end

    private

    def format_name(value)
      value.to_s.strip.downcase.split(" ").join("_")
    end
  end

  class MigrationBill < ActiveRecord::Base
    self.table_name = "bills"
  end

  class MigrationLegislatorVote < ActiveRecord::Base
    self.table_name = "legislator_votes"
  end

  def up
    # Step 1: nullable add (so existing rows don't violate NOT NULL pre-backfill)
    add_column :legislator_votes, :source, :string

    MigrationLegislatorVote.reset_column_information

    # Step 2: per-locale backfill via Ruby-side predicate dispatch.
    # We iterate sway_locales rows and use the stand-in predicates (congress? /
    # regional?) because they depend on RegionUtil mapping that
    # cannot be expressed in portable SQL. For each locale, we bulk-UPDATE
    # the legislator_votes rows whose bill belongs to that locale.
    MigrationSwayLocale.find_each do |locale|
      source = if locale.congress?
        "congress"
      elsif locale.regional?
        "open_states"
      else # local?
        "manual"
      end

      bill_ids = MigrationBill.where(sway_locale_id: locale.id).pluck(:id)
      next if bill_ids.empty?

      MigrationLegislatorVote.where(bill_id: bill_ids, source: nil)
        .update_all(source: source)
    end

    # Safety net for any orphan rows whose locale could not be resolved
    # (defensive — should be 0 in practice).
    MigrationLegislatorVote.where(source: nil).update_all(source: "manual")

    # Step 3: enforce NOT NULL after backfill
    change_column_null :legislator_votes, :source, false
  end

  def down
    remove_column :legislator_votes, :source
  end
end
