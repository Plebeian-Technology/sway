# typed: true

class CreateBillScores < ActiveRecord::Migration[7.1]
  def change
    create_table :bill_scores do |t|
      t.references :bill, null: false, foreign_key: true

      t.integer :for, null: false, default: 0
      t.integer :against, null: false, default: 0

      t.timestamps
    end
  end
end
