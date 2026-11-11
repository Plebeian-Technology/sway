# frozen_string_literal: true

# Locale-wide aggregate of users' agreement with a Legislator.
#
# @lat: [[scores-and-agreement#The five score families]]
class CreateLegislatorLocaleScores < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"
  end

  class MigrationLegislatorLocaleScore < ActiveRecord::Base
    self.table_name = "legislator_locale_scores"
  end

  def up
    create_table :legislator_locale_scores do |t|
      t.references :legislator, null: false, foreign_key: true, index: {unique: true}
      t.integer :count_agreed, null: false, default: 0
      t.integer :count_disagreed, null: false, default: 0
      t.integer :count_legislator_abstained, null: false, default: 0
      t.integer :count_no_legislator_vote, null: false, default: 0
      t.timestamps
    end

    # Backfill: every existing Legislator gets a default zeroed locale score so
    # the JSON shape is uniform once the model goes live. The score will be
    # recomputed organically by OnLegislatorVoteUpdateScoresJob on the next
    # legislator-vote change. For accurate seed values from day one, run the
    # rake task `sway:backfill:legislator_locale_scores` after deploy.
    now = Time.current
    MigrationLegislatorLocaleScore.reset_column_information
    rows = MigrationLegislator.pluck(:id).map do |legislator_id|
      {legislator_id: legislator_id, created_at: now, updated_at: now}
    end
    if rows.any?
      MigrationLegislatorLocaleScore.insert_all!(rows)
    end
  end

  def down
    drop_table :legislator_locale_scores
  end
end
