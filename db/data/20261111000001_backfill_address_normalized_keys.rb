# frozen_string_literal: true

# @lat: [[address-normalized-key#Why the backfill reports collisions instead of merging]]
class BackfillAddressNormalizedKeys < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationAddress < ActiveRecord::Base
    self.table_name = "addresses"

    encrypts :street2
    encrypts :street3
    encrypts :latitude
    encrypts :longitude
  end

  def up
    MigrationAddress.reset_column_information

    stats = Hash.new(0)

    # @lat: [[address-normalized-key#Finding an address during registration]]
    MigrationAddress.where(normalized_key: nil).find_each do |address|
      # @lat: [[migrations-name-no-model#The calculators a stand-in cannot replace]]
      key = Address.normalized_key_for(
        latitude: address.latitude,
        longitude: address.longitude,
        street2: address.street2,
        street3: address.street3
      )

      if key.nil?
        stats[:skipped_missing_coordinates] += 1
        next
      end

      address.update_columns(normalized_key: key)
      stats[:filled] += 1
    end

    SwayLogging.info("backfill_normalized_keys - stats=#{stats}")

    collisions = MigrationAddress.where.not(normalized_key: nil)
      .group(:normalized_key)
      .having(Arel.sql("COUNT(*) > 1"))
      .count

    say "filled #{stats[:filled]}, skipped (no coordinates) #{stats[:skipped_missing_coordinates]}."

    if collisions.empty?
      say "No normalized keys are shared by more than one row."
    else
      say "#{collisions.size} normalized key(s) shared by more than one row (not merged):"
      collisions.each_key do |normalized_key|
        ids = MigrationAddress.where(normalized_key:).order(:id).pluck(:id)
        say "  address ids #{ids.join(", ")}"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
