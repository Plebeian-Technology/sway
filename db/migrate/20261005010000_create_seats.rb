# frozen_string_literal: true

class CreateSeats < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:seats)
      create_table :seats do |t|
        t.references :district, null: false, foreign_key: true, index: true
        t.string :seat_identifier, null: false
        t.string :title, null: false
        t.string :chamber, null: false
        t.timestamps
      end
    end

    add_index :seats, :district_id unless index_exists?(:seats, :district_id)
    add_index :seats, %i[district_id seat_identifier], unique: true unless index_exists?(:seats, %i[district_id seat_identifier], unique: true)
  end
end
