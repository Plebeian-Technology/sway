# frozen_string_literal: true

class CascadeHistoricalScoreExplanationsOnUserDelete < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:historical_score_explanations)

    remove_foreign_key :historical_score_explanations, :users if foreign_key_exists?(:historical_score_explanations, :users)
    add_foreign_key :historical_score_explanations, :users, on_delete: :cascade
  end

  def down
    return unless table_exists?(:historical_score_explanations)

    remove_foreign_key :historical_score_explanations, :users if foreign_key_exists?(:historical_score_explanations, :users)
    add_foreign_key :historical_score_explanations, :users
  end
end
