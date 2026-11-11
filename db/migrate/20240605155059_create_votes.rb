class CreateVotes < ActiveRecord::Migration[7.1]
  def change
    create_table :votes do |t|
      t.integer :house_roll_call_vote_number
      t.integer :senate_roll_call_vote_number
      t.references :bill, null: false, foreign_key: true

      t.timestamps
    end
  end
end
