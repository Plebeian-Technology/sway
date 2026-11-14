# frozen_string_literal: true

class CascadeHistoricalRepairDeliveriesOnUserDelete < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:historical_repair_deliveries)

    remove_foreign_key :historical_repair_deliveries, :users if foreign_key_exists?(:historical_repair_deliveries, :users)
    add_foreign_key :historical_repair_deliveries, :users, on_delete: :cascade
  end

  def down
    return unless table_exists?(:historical_repair_deliveries)

    remove_foreign_key :historical_repair_deliveries, :users if foreign_key_exists?(:historical_repair_deliveries, :users)
    add_foreign_key :historical_repair_deliveries, :users
  end
end
