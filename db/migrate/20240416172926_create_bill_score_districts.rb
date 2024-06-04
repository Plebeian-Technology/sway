# typed: true

class CreateBillScoreDistricts < ActiveRecord::Migration[7.1]
  def change
    create_table :bill_score_districts do |t|
      t.references :bill_score, null: false, foreign_key: true
      t.references :district, null: false, foreign_key: true

      t.integer :for, null: false, default: 0
      t.integer :against, null: false, default: 0

      t.timestamps
    end
  end
end
