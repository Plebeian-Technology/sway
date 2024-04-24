# typed: true
class CreateBillScoreDistricts < ActiveRecord::Migration[7.1]
  def change
    create_table :bill_score_districts do |t|
      t.references :bill_score, null: false, foreign_key: true
      t.references :district, null: false, foreign_key: true

      t.integer :for
      t.integer :against

      t.timestamps
    end
  end
end
