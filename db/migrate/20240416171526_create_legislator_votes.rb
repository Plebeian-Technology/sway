# typed: true
class CreateLegislatorVotes < ActiveRecord::Migration[7.1]
  def change
    create_table :legislator_votes do |t|
      t.references :legislator, null: false, foreign_key: true
      t.references :bill, null: false, foreign_key: true
      t.string :support

      t.timestamps
    end
  end
end
