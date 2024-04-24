# typed: true
class CreateUserVotes < ActiveRecord::Migration[7.1]
  def change
    create_table :user_votes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :bill, null: false, foreign_key: true
      t.string :support

      t.timestamps
    end
  end
end
