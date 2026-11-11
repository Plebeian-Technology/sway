# frozen_string_literal: true

# @lat: [[address-normalized-key#Why the backfill reports collisions instead of merging]]
namespace :sway do
  namespace :addresses do
    desc "Backfill addresses.normalized_key for existing rows and report collisions"
    task backfill_normalized_keys: :environment do
      stats = Hash.new(0)

      Address.find_each do |address|
        key = address.computed_normalized_key

        if key.nil?
          stats[:skipped_missing_coordinates] += 1
          next
        end

        if address.normalized_key == key
          stats[:already_current] += 1
        else
          address.update_column(:normalized_key, key)
          stats[:filled] += 1
        end
      end

      SwayLogging.info("backfill_normalized_keys - stats=#{stats}")

      collisions = Address.where.not(normalized_key: nil)
        .group(:normalized_key)
        .having(Arel.sql("COUNT(*) > 1"))
        .count

      puts "sway:addresses:backfill_normalized_keys - filled #{stats[:filled]}, " \
        "already current #{stats[:already_current]}, " \
        "skipped (no coordinates) #{stats[:skipped_missing_coordinates]}."

      if collisions.empty?
        puts "No normalized keys are shared by more than one row."
      else
        puts "#{collisions.size} normalized key(s) shared by more than one row (not merged):"
        collisions.each_key do |normalized_key|
          ids = Address.where(normalized_key:).order(:id).pluck(:id)
          puts "  #{normalized_key} - address ids #{ids.join(", ")}"
        end
      end
    end
  end
end
