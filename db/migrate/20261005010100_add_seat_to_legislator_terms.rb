# frozen_string_literal: true

class AddSeatToLegislatorTerms < ActiveRecord::Migration[8.1]
  def change
    if column_exists?(:legislator_terms, :seat_id)
      add_index :legislator_terms, :seat_id unless index_exists?(:legislator_terms, :seat_id)
      unless foreign_key_exists?(:legislator_terms, :seats, column: :seat_id)
        add_foreign_key :legislator_terms, :seats, column: :seat_id
      end
    else
      add_reference :legislator_terms, :seat, foreign_key: true, index: true, null: true
    end
  end
end
