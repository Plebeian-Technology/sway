class CreateLegislatorDistrictScores < ActiveRecord::Migration[7.1]
  def change
    create_table :legislator_district_scores do |t|
      t.references :district, null: false, foreign_key: true
      t.references :legislator, null: false, foreign_key: true

      t.integer :count_agreed, null: false, default: 0
      t.integer :count_disagreed, null: false, default: 0
      t.integer :count_no_legislator_vote, null: false, default: 0
      t.integer :count_legislator_abstained, null: false, default: 0

      t.timestamps
    end
  end
end
