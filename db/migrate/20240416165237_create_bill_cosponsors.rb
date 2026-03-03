class CreateBillCosponsors < ActiveRecord::Migration[7.1]
  def change
    create_table :bill_cosponsors do |t|
      t.references :legislator, null: false, foreign_key: true
      t.references :bill, null: false, foreign_key: true

      t.timestamps
    end
  end
end
