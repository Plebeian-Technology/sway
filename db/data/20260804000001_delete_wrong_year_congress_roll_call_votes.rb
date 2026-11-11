# frozen_string_literal: true

# @lat: [[roll-call-identity#Identifying a congressional roll call#Why the year must be the year of the vote]]
class DeleteWrongYearCongressRollCallVotes < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
    alias_attribute :state, :region_name if column_names.include?("region_name")
  end

  class MigrationBill < ActiveRecord::Base
    self.table_name = "bills"
  end

  class MigrationLegislatorVote < ActiveRecord::Base
    self.table_name = "legislator_votes"
  end

  def up
    locale = MigrationSwayLocale.find_by(city: "congress", state: "congress")
    if locale.nil?
      say("no congress locale in this database; nothing to do")
      return
    end

    total = 0
    MigrationBill.where(sway_locale_id: locale.id).find_each do |bill|
      vote_year = [bill.house_vote_date_time_utc, bill.senate_vote_date_time_utc].compact.map(&:year).max
      next if vote_year.nil?

      rows = MigrationLegislatorVote.where(bill_id: bill.id, source: "congress", inferred: false)
      next unless rows.any? { |row| row.created_at.year > vote_year || row.updated_at.year > vote_year }

      deleted = rows.delete_all
      total += deleted
      say("#{bill.external_id}: deleted #{deleted} rows written or overwritten after its #{vote_year} vote")
    end

    say("deleted #{total} rows in all; the daily sweep re-fetches these bills with the right year")
  end

  # The deleted rows were a mixture of wrong values and right ones with no way
  # to tell them apart. The way back is the re-fetch, not an undo.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
