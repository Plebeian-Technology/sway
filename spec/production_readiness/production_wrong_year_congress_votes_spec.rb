# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislator-vote-sweep-design#What the wrong-year cleanup migration removes, and how the spec pins it]]
RSpec.describe "Production snapshot: wrong-year Congress roll-call rows", :production_snapshot do
  include_context "production snapshot (raw)"

  def select_value(sql)
    ActiveRecord::Base.connection.select_value(sql)
  end

  def select_values(sql)
    ActiveRecord::Base.connection.select_values(sql)
  end

  # Congress bills paired with the year of their newest chamber vote. Reads
  # only bills, sway_locales and legislator_votes, which look the same on
  # every snapshot generation this spec can meet.
  def congress_bill_years_sql
    <<~SQL
      SELECT b.id AS bill_id,
        MAX(substr(COALESCE(b.house_vote_date_time_utc, ''), 1, 4),
            substr(COALESCE(b.senate_vote_date_time_utc, ''), 1, 4)) AS vote_year
      FROM bills b
      JOIN sway_locales sl ON sl.id = b.sway_locale_id
      WHERE sl.city = 'congress' AND sl.state = 'congress'
    SQL
  end

  def wrong_year_row_count
    select_value(<<~SQL).to_i
      WITH cb AS (#{congress_bill_years_sql})
      SELECT COUNT(*)
      FROM cb
      JOIN legislator_votes lv ON lv.bill_id = cb.bill_id
      WHERE cb.vote_year != ''
        AND lv.source = 'congress' AND lv.inferred = 0
        AND (substr(lv.created_at, 1, 4) > cb.vote_year
             OR substr(lv.updated_at, 1, 4) > cb.vote_year)
    SQL
  end

  def condemned_bill_ids
    select_values(<<~SQL)
      WITH cb AS (#{congress_bill_years_sql})
      SELECT DISTINCT cb.bill_id
      FROM cb
      JOIN legislator_votes lv ON lv.bill_id = cb.bill_id
      WHERE cb.vote_year != ''
        AND lv.source = 'congress' AND lv.inferred = 0
        AND (substr(lv.created_at, 1, 4) > cb.vote_year
             OR substr(lv.updated_at, 1, 4) > cb.vote_year)
    SQL
  end

  # Everything the migration must leave alone, as one row of counts: manual
  # rows anywhere, inferred rows anywhere, and every row on bills outside the
  # congress locale.
  def untouched_counts
    select_value(<<~SQL)
      SELECT
        (SELECT COUNT(*) FROM legislator_votes WHERE source = 'manual') || '/' ||
        (SELECT COUNT(*) FROM legislator_votes WHERE inferred = 1) || '/' ||
        (SELECT COUNT(*) FROM legislator_votes lv
           JOIN bills b ON b.id = lv.bill_id
           JOIN sway_locales sl ON sl.id = b.sway_locale_id
           WHERE NOT (sl.city = 'congress' AND sl.state = 'congress'))
    SQL
  end

  it "removes every wrong-year row, empties the condemned bills, and touches nothing else" do
    if ProductionSnapshot.wrong_year_cleanup_applied?
      skip "cleanup migration already recorded on this snapshot; " \
        "later-year rows here were written by the FIXED fetcher and are correct"
    end

    before_wrong = wrong_year_row_count
    expect(before_wrong).to be > 0

    condemned = condemned_bill_ids
    expect(condemned).not_to be_empty

    before_untouched = untouched_counts

    ProductionSnapshot.migrate!

    expect(wrong_year_row_count).to eq(0)

    remaining_on_condemned = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM legislator_votes
      WHERE bill_id IN (#{condemned.join(",")})
        AND source = 'congress' AND inferred = 0
    SQL
    expect(remaining_on_condemned).to eq(0)

    expect(untouched_counts).to eq(before_untouched)
  end
end
