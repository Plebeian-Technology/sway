# frozen_string_literal: true

class AddLastSeededAtToSeededModels < ActiveRecord::Migration[8.1]
  def change
    add_column :legislators, :last_seeded_at, :datetime
    add_column :bills, :last_seeded_at, :datetime
    add_column :sway_locales, :last_seeded_at, :datetime
  end
end
