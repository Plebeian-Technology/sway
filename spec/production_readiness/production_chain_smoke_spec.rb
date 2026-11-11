# frozen_string_literal: true

require "rails_helper"

# @lat: [[production-chain-smoke-spec-design#What the vote-identity comparison actually protects]]
RSpec.describe "Production chain smoke (mid-phase Wave 4 gate)", :production_snapshot do
  include_context "production snapshot (raw)"

  def select_value(sql)
    ActiveRecord::Base.connection.select_value(sql)
  end

  def select_rows(sql)
    ActiveRecord::Base.connection.select_rows(sql)
  end

  it "applies the combined schema + db/data chain with zero exceptions, correct post-finalize shape, zero duplicate identities, and stable vote identities" do
    # @lat: [[production-chain-smoke-spec-design#What the vote-identity comparison actually protects]]
    skip "this snapshot has nothing pending — every migration in the repo has already run on it" if
      ProductionSnapshot.pending_migrations.empty?

    # @lat: [[production-chain-smoke-spec-design#What the vote-identity comparison actually protects]]
    locale_id, locale_join = ProductionSnapshot.locale_reached_by
    vote_identities_before = select_rows(<<~SQL)
      SELECT DISTINCT lv.bill_id, #{locale_id}, #{ProductionSnapshot.person_key_sql(locale_id)}
      FROM legislator_votes lv
      JOIN legislators l ON l.id = lv.legislator_id
      #{locale_join}
      #{ProductionSnapshot.wrong_year_cleanup_exclusion}
      ORDER BY 1, 2, 3
    SQL

    expect { ProductionSnapshot.migrate! }.not_to raise_error

    connection = ActiveRecord::Base.connection
    expect(ProductionSnapshot.pending_migrations).to be_empty
    expect(select_value("PRAGMA integrity_check")).to eq("ok")
    expect(select_rows("PRAGMA foreign_key_check")).to be_empty

    # (b) the table shape once the migrations have finished.
    expect(connection.column_exists?(:legislators, :district_id)).to be(false)
    expect(connection.column_exists?(:legislators, :active)).to be(false)
    expect(connection.column_exists?(:legislators, :title)).to be(false)
    expect(connection.column_exists?(:legislators, :sway_locale_id)).to be(true)
    expect(
      connection.index_exists?(:legislators, [:sway_locale_id, :external_id], unique: true)
    ).to be(true)
    expect(connection.table_exists?(:user_legislator_scores)).to be(false)
    expect(connection.column_exists?(:legislator_district_scores, :legislator_id)).to be(false)
    expect(connection.column_exists?(:legislator_locale_scores, :legislator_id)).to be(false)
    expect(connection.table_exists?(:legislator_terms)).to be(true)
    expect(connection.table_exists?(:user_legislator_term_scores)).to be(true)

    # (c) after conversion, no two legislators share a (sway_locale_id, external_id)
    # pair.
    expect(select_rows(<<~SQL)).to be_empty
      SELECT sway_locale_id, external_id
      FROM legislators
      GROUP BY sway_locale_id, external_id
      HAVING COUNT(*) > 1
    SQL

    # (d) every (bill, locale, person) vote survives the migration exactly once, now
    # pointing at the surviving person. Afterwards sway_locale_id sits directly on
    # legislators, so there is no district join.
    vote_identities_after = select_rows(<<~SQL)
      SELECT DISTINCT lv.bill_id, l.sway_locale_id, #{ProductionSnapshot.person_key_sql("l.sway_locale_id")}
      FROM legislator_votes lv
      JOIN legislators l ON l.id = lv.legislator_id
      ORDER BY 1, 2, 3
    SQL
    expect(vote_identities_after).to eq(vote_identities_before)
    expect(select_value("SELECT COUNT(*) FROM legislator_votes").to_i).to eq(vote_identities_before.length)
  end
end
