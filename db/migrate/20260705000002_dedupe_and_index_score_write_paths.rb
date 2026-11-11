# frozen_string_literal: true

# WS2.11: four race-prone find_or_create_by hot paths had no backing unique
# index, so concurrent creators split tallies (bill_scores, bill_score_districts),
# double-counted votes (legislator_votes — the LegislatorVoteUpserter's
# rescue ActiveRecord::RecordNotUnique could never fire), or sent duplicate
# legislator emails (user_legislator_emails). This migration dedupes existing
# rows one table at a time, then adds the composite unique index that lets the
# DB constraint resolve the race. The row DELETEs are irreversible; #down only
# restores the index shape.
class DedupeAndIndexScoreWritePaths < ActiveRecord::Migration[8.1]
  def up
    # 1. bill_scores — keep MIN(id) per bill_id. First drop the losing scores'
    #    district rows (they are recomputed from user_votes by the score
    #    redesign + the post-deploy sway:scores:recompute_all task), then the
    #    losing bill_scores, then swap the plain index for a unique one.
    execute(<<~SQL)
      DELETE FROM bill_score_districts
      WHERE bill_score_id IN (
        SELECT id FROM bill_scores
        WHERE id NOT IN (SELECT MIN(id) FROM bill_scores GROUP BY bill_id)
      );
    SQL
    execute(<<~SQL)
      DELETE FROM bill_scores
      WHERE id NOT IN (SELECT MIN(id) FROM bill_scores GROUP BY bill_id);
    SQL
    remove_index :bill_scores, name: "index_bill_scores_on_bill_id"
    add_index :bill_scores, :bill_id, unique: true

    # 2. bill_score_districts — keep MIN(id) per (bill_score_id, district_id).
    #    Runs after step 1 so every survivor points at a surviving bill_score.
    execute(<<~SQL)
      DELETE FROM bill_score_districts
      WHERE id NOT IN (
        SELECT MIN(id) FROM bill_score_districts
        GROUP BY bill_score_id, district_id
      );
    SQL
    add_index :bill_score_districts, [:bill_score_id, :district_id],
      unique: true, name: "index_bill_score_districts_on_bs_and_district"

    # 3. legislator_votes — dedupe honoring BOTH locked tiers of the
    #    LegislatorVoteUpserter contract: D-01 (admin/manual wins) AND CR-02
    #    (real-beats-inferred, legislator_vote_upserter.rb:61 "return false if
    #    inferred && !existing.inferred" — a synthetic sponsor-inferred row must
    #    never win over a real roll-call row). Per (bill_id, legislator_id) keep:
    #    the manual row if one exists; else the REAL (inferred=0) row over a
    #    synthetic one; else the most-recently-updated (id breaks ties). Without
    #    the (inferred = 0) tier, a pre-index race that left a real + a
    #    more-recently-updated synthetic row would delete the REAL vote. No
    #    upserter logic changes — the index just makes its RecordNotUnique rescue
    #    live.
    execute(<<~SQL)
      DELETE FROM legislator_votes
      WHERE id NOT IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (
            PARTITION BY bill_id, legislator_id
            ORDER BY (source = 'manual') DESC, (inferred = 0) DESC, updated_at DESC, id DESC
          ) AS rn
          FROM legislator_votes
        ) ranked
        WHERE ranked.rn = 1
      );
    SQL
    add_index :legislator_votes, [:bill_id, :legislator_id], unique: true

    # 4. user_legislator_emails — keep MIN(id) per (user_legislator_id, bill_id).
    #    bill_id is nullable; SQLite treats NULLs as distinct in a unique index,
    #    so only dedupe rows with a real bill (matching the index's semantics).
    execute(<<~SQL)
      DELETE FROM user_legislator_emails
      WHERE bill_id IS NOT NULL
        AND id NOT IN (
          SELECT MIN(id) FROM user_legislator_emails
          WHERE bill_id IS NOT NULL
          GROUP BY user_legislator_id, bill_id
        );
    SQL
    add_index :user_legislator_emails, [:user_legislator_id, :bill_id],
      unique: true, name: "index_user_legislator_emails_on_ul_and_bill"
  end

  def down
    remove_index :user_legislator_emails,
      name: "index_user_legislator_emails_on_ul_and_bill"
    remove_index :legislator_votes,
      name: "index_legislator_votes_on_bill_id_and_legislator_id"
    remove_index :bill_score_districts,
      name: "index_bill_score_districts_on_bs_and_district"
    remove_index :bill_scores, name: "index_bill_scores_on_bill_id"
    add_index :bill_scores, :bill_id
  end
end
