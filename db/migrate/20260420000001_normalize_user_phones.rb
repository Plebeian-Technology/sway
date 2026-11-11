# frozen_string_literal: true

class NormalizeUserPhones < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # @lat: [[migrate-from-empty-spec-design#The failure pattern]]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    say_with_time "Normalizing users.phone to 10 digits" do
      MigrationUser.reset_column_information

      plan = []
      invalid = []
      collisions = []

      MigrationUser.where.not(phone: [nil, ""]).find_each do |user|
        normalized = user.phone.to_s.normalize_phone
        next if normalized == user.phone

        if normalized.length != 10
          invalid << [user.id, user.phone, normalized]
          next
        end

        conflict_id = MigrationUser.where(phone: normalized).where.not(id: user.id).pick(:id)
        if conflict_id
          collisions << [user.id, user.phone, conflict_id]
          next
        end

        plan << [user.id, normalized]
      end

      invalid.each do |id, old, new_|
        say "skip user=#{id} phone=#{old.inspect} -> #{new_.inspect} (not 10 digits)", true
      end
      collisions.each do |id, old, other|
        say "skip user=#{id} phone=#{old.inspect} (conflicts with user=#{other})", true
      end

      plan.each do |id, new_phone|
        MigrationUser.where(id: id).update_all(phone: new_phone) # rubocop:disable Rails/SkipsModelValidations
      end

      say "normalized #{plan.size}, skipped #{invalid.size + collisions.size} " \
        "(#{invalid.size} invalid length, #{collisions.size} collisions)"
      plan.size
    end
  end

  def down
    # Irreversible: original formatting is not preserved.
  end
end
