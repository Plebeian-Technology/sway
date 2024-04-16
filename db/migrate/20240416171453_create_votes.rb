class CreateVotes < ActiveRecord::Migration[7.1]
  def change
    create_table :votes do |t|
      t.datetime :voted_on_utc
      t.references :bill, null: false, foreign_key: true

      t.timestamps
    end
  end
end
