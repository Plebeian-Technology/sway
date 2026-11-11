# frozen_string_literal: true

require "rails_helper"

# @lat: [[production-snapshot-deploy-rehearsal-harness#Why production_migration_spec.rb's helper queries come in two shapes]]
RSpec.describe "Production snapshot migration", :production_snapshot do
  include_context "production snapshot (raw)"

  def select_rows(sql)
    ActiveRecord::Base.connection.select_rows(sql)
  end

  def select_value(sql)
    ActiveRecord::Base.connection.select_value(sql)
  end

  # @lat: [[production-migration-spec-design#Why the vote/link/sponsor helper queries carve out wrong-year cleanup rows]]
  def raw_vote_identities
    locale_id, locale_join = ProductionSnapshot.locale_reached_by
    select_rows(<<~SQL)
      SELECT DISTINCT lv.bill_id, #{locale_id}, #{ProductionSnapshot.person_key_sql(locale_id)}
      FROM legislator_votes lv
      JOIN legislators l ON l.id = lv.legislator_id
      #{locale_join}
      #{ProductionSnapshot.wrong_year_cleanup_exclusion}
      ORDER BY 1, 2, 3
    SQL
  end

  # Before the migration: every user-to-representative link, keyed by the person.
  def raw_user_legislator_identities
    locale_id, locale_join = ProductionSnapshot.locale_reached_by
    select_rows(<<~SQL)
      SELECT DISTINCT ul.user_id, #{locale_id}, #{ProductionSnapshot.person_key_sql(locale_id)}
      FROM user_legislators ul
      JOIN legislators l ON l.id = ul.legislator_id
      #{locale_join}
      ORDER BY 1, 2, 3
    SQL
  end

  # Before the migration: every bill-to-sponsor link, keyed by the person.
  def raw_sponsor_identities
    locale_id, locale_join = ProductionSnapshot.locale_reached_by
    select_rows(<<~SQL)
      SELECT b.id, #{locale_id}, #{ProductionSnapshot.person_key_sql(locale_id)}
      FROM bills b
      JOIN legislators l ON l.id = b.legislator_id
      #{locale_join}
      ORDER BY 1, 2, 3
    SQL
  end

  # After the migration: the same facts read from the new shape. sway_locale_id is a
  # column on legislators now, so there is no district join and no district_id.
  def migrated_vote_identities
    select_rows(<<~SQL)
      SELECT DISTINCT lv.bill_id, l.sway_locale_id, #{ProductionSnapshot.person_key_sql("l.sway_locale_id")}
      FROM legislator_votes lv
      JOIN legislators l ON l.id = lv.legislator_id
      ORDER BY 1, 2, 3
    SQL
  end

  def migrated_user_legislator_identities
    select_rows(<<~SQL)
      SELECT DISTINCT ul.user_id, l.sway_locale_id, #{ProductionSnapshot.person_key_sql("l.sway_locale_id")}
      FROM user_legislators ul
      JOIN legislators l ON l.id = ul.legislator_id
      ORDER BY 1, 2, 3
    SQL
  end

  def migrated_sponsor_identities
    select_rows(<<~SQL)
      SELECT b.id, l.sway_locale_id, #{ProductionSnapshot.person_key_sql("l.sway_locale_id")}
      FROM bills b
      JOIN legislators l ON l.id = b.legislator_id
      ORDER BY 1, 2, 3
    SQL
  end

  # Passkey data has to come out of the deploy exactly as it went in. That is the
  # promise that passkey work can never lock a production user out of their account.
  # The column list here is the one from before the migration; any column a migration
  # adds, such as aaguid, is checked separately.
  def snapshot_passkey_rows
    select_rows(<<~SQL)
      SELECT id, user_id, label, external_id, public_key, sign_count,
             last_used_at, created_at, updated_at
      FROM passkeys
      ORDER BY id
    SQL
  end

  it "applies every pending migration and preserves user-facing data" do
    # @lat: [[production-migration-spec-design#Why a caught-up snapshot skips instead of fails]]
    skip "this snapshot has nothing pending — every migration in the repo has already run on it" if
      ProductionSnapshot.pending_migrations.empty?

    users_before = select_rows(
      "SELECT id, phone, is_registration_complete FROM users ORDER BY id"
    )
    passkeys_before = snapshot_passkey_rows
    bills_before = select_value("SELECT COUNT(*) FROM bills")
    organizations_before = select_value("SELECT COUNT(*) FROM organizations")
    user_votes_before = select_rows(
      "SELECT user_id, bill_id FROM user_votes ORDER BY user_id, bill_id"
    )
    vote_identities_before = raw_vote_identities
    user_legislator_identities_before = raw_user_legislator_identities
    sponsor_identities_before = raw_sponsor_identities
    # Every (locale, external_id) pair, and every human, that the snapshot holds going
    # in. Both sets are compared after the run rather than just their sizes, because a
    # count that comes out right can still be right for the wrong reason.
    locale_id, locale_join = ProductionSnapshot.locale_reached_by
    legislator_keys_before = select_rows(<<~SQL)
      SELECT DISTINCT #{locale_id}, l.external_id
      FROM legislators l
      #{locale_join}
      ORDER BY 1, 2
    SQL
    people_before = select_rows(<<~SQL)
      SELECT DISTINCT #{locale_id}, LOWER(l.first_name), LOWER(l.last_name)
      FROM legislators l
      #{locale_join}
      ORDER BY 1, 2, 3
    SQL
    baltimore_locale_id = ProductionSnapshot.baltimore_locale_id

    ProductionSnapshot.migrate!

    connection = ActiveRecord::Base.connection
    expect(ProductionSnapshot.pending_migrations).to be_empty
    expect(select_value("PRAGMA integrity_check")).to eq("ok")
    expect(select_rows("PRAGMA foreign_key_check")).to be_empty

    # Users and their credentials are untouched.
    expect(
      select_rows("SELECT id, phone, is_registration_complete FROM users ORDER BY id")
    ).to eq(users_before)
    expect(snapshot_passkey_rows).to eq(passkeys_before)
    expect(connection.column_exists?(:users, :is_admin)).to be(false)
    expect(connection.column_exists?(:passkeys, :aaguid)).to be(true)

    # Content survives.
    expect(select_value("SELECT COUNT(*) FROM bills")).to eq(bills_before)
    expect(select_value("SELECT COUNT(*) FROM organizations")).to eq(organizations_before)
    expect(
      select_rows("SELECT user_id, bill_id FROM user_votes ORDER BY user_id, bill_id")
    ).to eq(user_votes_before)

    # This chain drops the district_id, active and title columns from legislators.
    expect(connection.column_exists?(:legislators, :district_id)).to be(false)
    expect(connection.column_exists?(:legislators, :active)).to be(false)
    expect(connection.column_exists?(:legislators, :title)).to be(false)

    # @lat: [[production-migration-spec-design#Why the legislator dedup check compares facts, not the raw row count]]
    expect(select_rows(<<~SQL)).to be_empty
      SELECT sway_locale_id, external_id
      FROM legislators
      GROUP BY sway_locale_id, external_id
      HAVING COUNT(*) > 1
    SQL

    # @lat: [[migrations-name-no-model#What a rehearsal against production data checks]]
    expect(select_rows(<<~SQL)).to eq(people_before)
      SELECT DISTINCT l.sway_locale_id, LOWER(l.first_name), LOWER(l.last_name)
      FROM legislators l
      ORDER BY 1, 2, 3
    SQL

    # @lat: [[migrations-name-no-model#What a rehearsal against production data checks]]
    legislator_keys_after = select_rows(
      "SELECT DISTINCT sway_locale_id, external_id FROM legislators ORDER BY 1, 2"
    )

    # @lat: [[production-migration-spec-design#Why the Baltimore re-key admission check is narrow]]
    invented =
      (legislator_keys_after - legislator_keys_before).reject { |locale_id, key|
        seat, name_key = key.to_s.split("|", 2)
        locale_id == baltimore_locale_id &&
          name_key.present? &&
          legislator_keys_before.include?([locale_id, seat])
      }
    expect(invented).to be_empty,
      "the chain invented legislator keys nothing published: #{invented.inspect}"

    retired_keys = legislator_keys_before - legislator_keys_after
    expect(retired_keys.map(&:first).uniq - [baltimore_locale_id]).to be_empty

    vote_identities_after = migrated_vote_identities
    user_legislator_identities_after = migrated_user_legislator_identities
    sponsor_identities_after = migrated_sponsor_identities

    expect(vote_identities_after).to eq(vote_identities_before)
    expect(user_legislator_identities_after).to eq(user_legislator_identities_before)
    expect(sponsor_identities_after).to eq(sponsor_identities_before)

    # @lat: [[production-migration-spec-design#Why the post-migration duplication check reads rows, not identities]]
    expect(select_rows(<<~SQL)).to be_empty
      SELECT bill_id, legislator_id
      FROM legislator_votes
      GROUP BY bill_id, legislator_id
      HAVING COUNT(*) > 1
    SQL
    expect(select_rows(<<~SQL)).to be_empty
      SELECT user_id, legislator_id
      FROM user_legislators
      GROUP BY user_id, legislator_id
      HAVING COUNT(*) > 1
    SQL

    # @lat: [[legislator-term-current-and-covering#Why .covering returns nil instead of guessing#What production_migration_spec.rb's term-coverage guard checks]]
    terms_by_legislator_id =
      LegislatorTerm.includes(district: :sway_locale).all.group_by(&:legislator_id)

    legislators_with_votes = LegislatorVote.distinct.pluck(:legislator_id)
    legislators_without_any_term = legislators_with_votes - terms_by_legislator_id.keys
    expect(legislators_without_any_term).to be_empty,
      "#{legislators_without_any_term.length} legislator(s) with votes have ZERO " \
        "legislator_terms rows — LegislatorTerm.covering returns nil for them and " \
        "scoring would silently drop their agreement contribution " \
        "#{legislators_without_any_term.first(5)}"
  end
end
