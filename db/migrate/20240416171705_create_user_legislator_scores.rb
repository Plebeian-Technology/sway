# typed: true
class CreateUserLegislatorScores < ActiveRecord::Migration[7.1]
  def change
    create_table :user_legislator_scores do |t|
      t.references :user_legislator, null: false, foreign_key: true
      t.integer :count_agreed
      t.integer :count_disagreed
      t.integer :count_no_legislator_vote
      t.integer :count_legislator_abstained

      t.timestamps
    end
  end
end
