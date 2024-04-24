# typed: true
class CreateBillScores < ActiveRecord::Migration[7.1]
  def change
    create_table :bill_scores do |t|
      t.references :bill, null: false, foreign_key: true

      t.timestamps
    end
  end
end
