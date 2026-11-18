class AddDistinctVoterCountToLegislatorScores < ActiveRecord::Migration[8.1]
  def change
    add_column :legislator_district_scores, :distinct_voter_count, :integer, default: 0, null: false
    add_column :legislator_locale_scores, :distinct_voter_count, :integer, default: 0, null: false
  end
end
