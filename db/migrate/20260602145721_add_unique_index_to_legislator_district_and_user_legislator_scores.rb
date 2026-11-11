# frozen_string_literal: true

# @lat: [[migrations-name-no-model#Migrations name no model#A uniqueness validation is not a constraint]]
class AddUniqueIndexToLegislatorDistrictAndUserLegislatorScores < ActiveRecord::Migration[8.1]
  def up
    dedupe_keep_latest(:legislator_district_scores, :legislator_id)
    dedupe_keep_latest(:user_legislator_scores, :user_legislator_id)

    swap_to_unique(
      :legislator_district_scores,
      :legislator_id,
      "index_legislator_district_scores_on_legislator_id",
    )
    swap_to_unique(
      :user_legislator_scores,
      :user_legislator_id,
      "index_user_legislator_scores_on_user_legislator_id",
    )
  end

  def down
    swap_to_non_unique(
      :legislator_district_scores,
      :legislator_id,
      "index_legislator_district_scores_on_legislator_id",
    )
    swap_to_non_unique(
      :user_legislator_scores,
      :user_legislator_id,
      "index_user_legislator_scores_on_user_legislator_id",
    )
  end

  private

  # Keep the most-recent row per key (MAX(id)); delete older duplicates. These
  # are recomputed aggregate scores, so the surviving row is refreshed by the
  # score-update jobs anyway — this only clears accidental race-created dupes so
  # the unique index can be added. (No-op when there are no duplicates.)
  def dedupe_keep_latest(table, key)
    execute(<<~SQL.squish)
      DELETE FROM #{table}
      WHERE id NOT IN (SELECT MAX(id) FROM #{table} GROUP BY #{key})
    SQL
  end

  def swap_to_unique(table, column, name)
    remove_index table, name: name
    add_index table, column, unique: true, name: name
  end

  def swap_to_non_unique(table, column, name)
    remove_index table, name: name
    add_index table, column, name: name
  end
end
