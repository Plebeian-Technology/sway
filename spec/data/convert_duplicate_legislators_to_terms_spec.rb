# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260711000004_convert_duplicate_legislators_to_terms")

# @lat: [[legislator-term-conversion-fixture-design#Why this migration spec's fixture is shaped the way it is]]
RSpec.describe "ConvertDuplicateLegislatorsToTerms data migration", type: :model do
  self.use_transactional_tests = false

  # steep:ignore:start
  before(:all) do
    conn = ActiveRecord::Base.connection

    @added_legislator_columns = []
    {district_id: :integer, active: :boolean, title: :string}.each do |name, type|
      next if conn.column_exists?(:legislators, name)

      conn.add_column(:legislators, name, type)
      @added_legislator_columns << name
    end

    # @lat: [[legislator-term-conversion-fixture-design#Staying green across two later cleanup migrations]]
    @removed_identity_index = conn.index_exists?(:legislators, [:sway_locale_id, :external_id], unique: true)
    conn.remove_index(:legislators, [:sway_locale_id, :external_id]) if @removed_identity_index

    @relaxed_sway_locale_null = !conn.columns(:legislators).find { |c| c.name == "sway_locale_id" }.null
    conn.change_column_null(:legislators, :sway_locale_id, true) if @relaxed_sway_locale_null

    @added_score_legislator_id_tables = []
    @relaxed_term_id_null_tables = []
    %i[legislator_district_scores legislator_locale_scores legislator_votes].each do |table|
      unless conn.column_exists?(table, :legislator_id)
        conn.add_column(table, :legislator_id, :integer)
        @added_score_legislator_id_tables << table
      end

      unless conn.columns(table).find { |c| c.name == "legislator_term_id" }.null
        conn.change_column_null(table, :legislator_term_id, true)
        @relaxed_term_id_null_tables << table
      end
    end

    @created_user_legislator_scores_table = !conn.table_exists?(:user_legislator_scores)
    if @created_user_legislator_scores_table
      conn.create_table :user_legislator_scores do |t|
        t.integer :user_legislator_id, null: false
        t.integer :count_agreed, default: 0, null: false
        t.integer :count_disagreed, default: 0, null: false
        t.integer :count_no_legislator_vote, default: 0, null: false
        t.integer :count_legislator_abstained, default: 0, null: false
        t.timestamps
      end
      conn.add_index :user_legislator_scores, :user_legislator_id, unique: true
    end

    [Legislator, LegislatorDistrictScore, LegislatorLocaleScore, LegislatorVote].each(&:reset_column_information)

    build_fixture!
    ConvertDuplicateLegislatorsToTerms.new.up
  end

  after(:all) do
    cleanup_fixture!

    conn = ActiveRecord::Base.connection
    Array(@added_legislator_columns).each { |name| conn.remove_column(:legislators, name) }
    Array(@added_score_legislator_id_tables).each { |table| conn.remove_column(table, :legislator_id) }
    Array(@relaxed_term_id_null_tables).each { |table| conn.change_column_null(table, :legislator_term_id, false) }
    conn.change_column_null(:legislators, :sway_locale_id, false) if @relaxed_sway_locale_null
    conn.add_index(:legislators, [:sway_locale_id, :external_id], unique: true) if @removed_identity_index
    conn.drop_table(:user_legislator_scores) if @created_user_legislator_scores_table

    [Legislator, LegislatorDistrictScore, LegislatorLocaleScore, LegislatorVote].each(&:reset_column_information)
  end

  def raw_legislator!(external_id:, district:, title:, created_at:, active: true)
    legislator = Legislator.new(
      external_id: external_id,
      district_id: district.id,
      title: title,
      active: active,
      first_name: "Test",
      last_name: external_id,
      party: "D"
    )
    legislator.save!(validate: false)
    legislator.update_columns(created_at: created_at, updated_at: created_at, last_seeded_at: nil, sway_locale_id: nil)
    legislator
  end

  def build_fixture!
    @congress_locale = SwayLocale.find_or_create_by!(city: "congress", state: "congress", country: "united_states")
    @district_ga6 = District.find_or_create_by!(name: "GA6", sway_locale: @congress_locale)
    @district_ga7 = District.find_or_create_by!(name: "GA7", sway_locale: @congress_locale)
    @district_r1 = District.find_or_create_by!(name: "R1", sway_locale: @congress_locale)
    @district_lone = District.find_or_create_by!(name: "LN1", sway_locale: @congress_locale)
    @district_s1 = District.find_or_create_by!(name: "S1", sway_locale: @congress_locale)

    # McCormick: same external_id, two rows from different dates, in different
    # districts because the map was redrawn -> two legislator_terms rows hanging
    # off one canonical person.
    @mccormick_2024 = raw_legislator!(
      external_id: "M001218", district: @district_ga6, title: "Rep.", created_at: Time.zone.local(2024, 5, 15)
    )
    @mccormick_2025 = raw_legislator!(
      external_id: "M001218", district: @district_ga7, title: "Rep.", created_at: Time.zone.local(2025, 1, 20)
    )

    # A duplicate group of the common kind: the same seat seeded three separate
    # times -- May-2024 (118th Congress), then Jan-2025 and Aug-2025, which both
    # land on one 119th term.
    @r1_may2024 = raw_legislator!(
      external_id: "R000001", district: @district_r1, title: "Rep.", created_at: Time.zone.local(2024, 5, 1)
    )
    @r1_jan2025 = raw_legislator!(
      external_id: "R000001", district: @district_r1, title: "Rep.", created_at: Time.zone.local(2025, 1, 20)
    )
    @r1_aug2025 = raw_legislator!(
      external_id: "R000001", district: @district_r1, title: "Rep.", created_at: Time.zone.local(2025, 8, 1)
    )

    # A vote attached to a row that will lose the merge (r1_may2024). It has to
    # survive, pointed at whichever row the conversion picks as canonical.
    @bill = create(:bill, sway_locale: @congress_locale, legislator: @r1_aug2025, scheduled_release_date_utc: 3.days.ago)
    @preserved_vote = LegislatorVote.new(
      bill: @bill, legislator: @r1_may2024, support: LegislatorVote::Support::FOR, source: "manual"
    )
    @preserved_vote.save!(validate: false)

    # Sponsorship and cosponsorship attached to rows that will lose the merge.
    @sponsor_bill = create(:bill, sway_locale: @congress_locale, legislator: @r1_may2024, scheduled_release_date_utc: 2.days.ago)
    @cosponsor_bill = create(:bill, sway_locale: @congress_locale, legislator: @r1_aug2025, scheduled_release_date_utc: 1.day.ago)
    @preserved_cosponsor = BillCosponsor.create!(bill: @cosponsor_bill, legislator: @r1_jan2025)

    # @lat: [[legislator-term-conversion-fixture-design#Why a non-zero score on a losing row is saved with validate: false]]
    @loser_district_score = LegislatorDistrictScore.new(legislator_id: @r1_may2024.id, count_agreed: 3, count_disagreed: 1)
    @loser_district_score.save!(validate: false)
    @loser_locale_score = LegislatorLocaleScore.new(legislator_id: @r1_may2024.id, count_agreed: 5, count_disagreed: 2)
    @loser_locale_score.save!(validate: false)

    # @lat: [[legislator-term-conversion-fixture-design#The two-generation same-term collision (newer updated_at wins)]]
    @stale_2025_locale_score = LegislatorLocaleScore.new(legislator_id: @r1_jan2025.id, count_agreed: 1)
    @stale_2025_locale_score.save!(validate: false)
    @stale_2025_locale_score.update_columns(updated_at: Time.zone.local(2025, 1, 21))
    @fresh_2025_locale_score = LegislatorLocaleScore.new(legislator_id: @r1_aug2025.id, count_agreed: 9)
    @fresh_2025_locale_score.save!(validate: false)
    @fresh_2025_locale_score.update_columns(updated_at: Time.zone.local(2025, 8, 2))

    # A user_legislator and an old-style score on a row that loses the merge,
    # where this user has no link to the canonical row yet -> a plain repoint
    # and score move.
    @plain_user = create(:user)
    @plain_user_legislator = UserLegislator.new(user: @plain_user, legislator: @r1_jan2025)
    @plain_user_legislator.save!(validate: false)
    insert_legacy_score!(@plain_user_legislator, count_agreed: 4, count_disagreed: 1)

    # A user with a link to a losing row and an already-existing link to the
    # canonical row. The losing link and its old score have to fold into the
    # surviving link as a new term-scoped row, not quietly disappear.
    @dup_user = create(:user)
    @dup_user_legislator_loser = UserLegislator.new(user: @dup_user, legislator: @r1_may2024, active: true)
    @dup_user_legislator_loser.save!(validate: false)
    insert_legacy_score!(@dup_user_legislator_loser, count_agreed: 2, count_disagreed: 2)
    @dup_user_legislator_survivor = UserLegislator.new(user: @dup_user, legislator: @r1_aug2025, active: true)
    @dup_user_legislator_survivor.save!(validate: false)

    # @lat: [[legislator-term-conversion-fixture-design#The lone, never-duplicated legislator case]]
    @lone_legislator = raw_legislator!(
      external_id: "L000001", district: @district_lone, title: "Rep.", created_at: Time.zone.local(2025, 3, 1)
    )
    @lone_user = create(:user)
    @lone_user_legislator = UserLegislator.new(user: @lone_user, legislator: @lone_legislator, active: true)
    @lone_user_legislator.save!(validate: false)
    insert_legacy_score!(@lone_user_legislator, count_agreed: 6, count_disagreed: 3)

    # @lat: [[legislator-term-conversion-fixture-design#The same-user, same-term collision across two losing rows]]
    @s1_feb2025 = raw_legislator!(
      external_id: "S000001", district: @district_s1, title: "Rep.", created_at: Time.zone.local(2025, 2, 1)
    )
    @s1_jun2025 = raw_legislator!(
      external_id: "S000001", district: @district_s1, title: "Rep.", created_at: Time.zone.local(2025, 6, 1)
    )
    @s1_sep2025 = raw_legislator!(
      external_id: "S000001", district: @district_s1, title: "Rep.", created_at: Time.zone.local(2025, 9, 1)
    )
    @collision_user = create(:user)
    # @lat: [[legislator-term-conversion-fixture-design#Why the collision fixtures are created in id order]]
    @collision_user_a = UserLegislator.new(user: @collision_user, legislator: @s1_feb2025, active: true)
    @collision_user_a.save!(validate: false)
    insert_legacy_score!(@collision_user_a, count_agreed: 2, count_disagreed: 1)
    @collision_user_b = UserLegislator.new(user: @collision_user, legislator: @s1_jun2025, active: true)
    @collision_user_b.save!(validate: false)
    insert_legacy_score!(@collision_user_b, count_agreed: 5, count_disagreed: 0)
  end

  # UserLegislator still has an after_create_commit callback that makes an empty
  # score row as soon as the link is created. Upsert instead of a plain INSERT,
  # so this works whether or not that callback has already run.
  def insert_legacy_score!(user_legislator, count_agreed:, count_disagreed:)
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO user_legislator_scores
        (user_legislator_id, count_agreed, count_disagreed, count_no_legislator_vote, count_legislator_abstained, created_at, updated_at)
      VALUES
        (#{user_legislator.id}, #{count_agreed}, #{count_disagreed}, 0, 0, '#{Time.current.utc}', '#{Time.current.utc}')
      ON CONFLICT(user_legislator_id) DO UPDATE SET
        count_agreed = excluded.count_agreed,
        count_disagreed = excluded.count_disagreed
    SQL
  end

  def cleanup_fixture!
    conn = ActiveRecord::Base.connection
    conn.disable_referential_integrity do
      external_ids = %w[M001218 R000001 L000001 S000001]
      legislator_ids = Legislator.where(external_id: external_ids).pluck(:id)
      bill_ids = [@bill&.id, @sponsor_bill&.id, @cosponsor_bill&.id].compact
      fixture_users = [@plain_user, @dup_user, @lone_user, @collision_user].compact
      district_ids = [@district_ga6, @district_ga7, @district_r1, @district_lone, @district_s1].compact.map(&:id)

      UserLegislatorTermScore.where(user_legislator_id: UserLegislator.where(user: fixture_users).select(:id)).delete_all
      conn.execute("DELETE FROM user_legislator_scores WHERE user_legislator_id IN (SELECT id FROM user_legislators WHERE user_id IN (#{fixture_users.map(&:id).join(",")}))") if fixture_users.any?
      UserDistrict.where(district_id: district_ids).delete_all if district_ids.any?
      UserDistrict.where(user_id: fixture_users.map(&:id)).delete_all if fixture_users.any?
      UserLegislator.where(user: fixture_users).delete_all if fixture_users.any?
      User.where(id: fixture_users.map(&:id)).delete_all if fixture_users.any?

      LegislatorDistrictScore.where(legislator_id: legislator_ids).delete_all if legislator_ids.any?
      LegislatorLocaleScore.where(legislator_id: legislator_ids).delete_all if legislator_ids.any?
      LegislatorVote.where(bill_id: bill_ids).delete_all if bill_ids.any?
      BillCosponsor.where(bill_id: bill_ids).delete_all if bill_ids.any?
      LegislatorTerm.where(legislator_id: legislator_ids).delete_all if legislator_ids.any?
      Bill.where(id: bill_ids).delete_all if bill_ids.any?
      Legislator.where(external_id: external_ids).delete_all if external_ids.any?
      District.where(id: district_ids).delete_all if district_ids.any?
      SwayLocale.where(id: @congress_locale&.id).delete_all if @congress_locale
    end
  end
  # steep:ignore:end

  it "consolidates each duplicate group down to one canonical person (zero duplicate identities)" do
    expect(Legislator.where(external_id: "M001218").count).to eq(1)
    expect(Legislator.where(external_id: "R000001").count).to eq(1)
  end

  it "backfills sway_locale_id on the canonical row" do
    canonical = Legislator.find_by!(external_id: "R000001")
    expect(canonical.sway_locale_id).to eq(@congress_locale.id)
  end

  it "buckets May-2024 into the 118th term and Jan+Aug-2025 into one 119th term" do
    canonical = Legislator.find_by!(external_id: "R000001")
    terms = LegislatorTerm.where(legislator: canonical).order(:term_start_year)

    expect(terms.pluck(:term_start_year)).to eq([2023, 2025])
    # Jan-2025 and Aug-2025 converge on the SAME term row (not two).
    expect(LegislatorTerm.where(legislator: canonical, term_start_year: 2025).count).to eq(1)
  end

  it "splits McCormick's redistricting into a GA6 118th term and a GA7 119th term" do
    canonical = Legislator.find_by!(external_id: "M001218")
    terms = LegislatorTerm.where(legislator: canonical).order(:term_start_year)

    expect(terms.map { |t| [t.term_start_year, t.district_id] }).to eq(
      [[2023, @district_ga6.id], [2025, @district_ga7.id]]
    )
  end

  it "preserves the legislator_vote identity, repointed to the canonical person" do
    canonical = Legislator.find_by!(external_id: "R000001")
    expect(@preserved_vote.reload.legislator_id).to eq(canonical.id)
    expect(@preserved_vote.support).to eq(LegislatorVote::Support::FOR)
  end

  it "repoints bill sponsorship and cosponsorship to the canonical person" do
    canonical = Legislator.find_by!(external_id: "R000001")
    expect(@sponsor_bill.reload.legislator_id).to eq(canonical.id)
    expect(@preserved_cosponsor.reload.legislator_id).to eq(canonical.id)
  end

  it "re-derives the loser's legislator_district_score/legislator_locale_score onto its term, never discarding it" do
    canonical = Legislator.find_by!(external_id: "R000001")
    term_2023 = LegislatorTerm.find_by!(legislator: canonical, term_start_year: 2023)

    district_score = LegislatorDistrictScore.find(@loser_district_score.id)
    locale_score = LegislatorLocaleScore.find(@loser_locale_score.id)

    expect(district_score.legislator_term_id).to eq(term_2023.id)
    # legislator_id only exists here as a stopgap; on a real deploy the clean-up
    # migration drops it after this data migration has run. Read it raw rather
    # than through a model accessor, which steep would reject against the final
    # schema.
    expect(district_score.read_attribute(:legislator_id)).to eq(canonical.id)
    expect(district_score.count_agreed).to eq(3)
    expect(locale_score.legislator_term_id).to eq(term_2023.id)
    expect(locale_score.count_agreed).to eq(5)
  end

  it "resolves score rows CONVERGING on one term by keeping the freshest and dropping the superseded snapshot" do
    canonical = Legislator.find_by!(external_id: "R000001")
    term_2025 = LegislatorTerm.find_by!(legislator: canonical, term_start_year: 2025)

    winner = LegislatorLocaleScore.find_by!(legislator_term_id: term_2025.id)
    expect(winner.id).to eq(@fresh_2025_locale_score.id)
    expect(winner.count_agreed).to eq(9)
    expect(LegislatorLocaleScore.where(id: @stale_2025_locale_score.id)).not_to exist
  end

  it "repoints a non-colliding user_legislator and migrates its legacy score into a UserLegislatorTermScore" do
    canonical = Legislator.find_by!(external_id: "R000001")
    term_2025 = LegislatorTerm.find_by!(legislator: canonical, term_start_year: 2025)

    survivor = UserLegislator.find(@plain_user_legislator.id)
    expect(survivor.legislator_id).to eq(canonical.id)

    term_score = UserLegislatorTermScore.find_by(user_legislator: survivor, legislator_term: term_2025)
    expect(term_score).to be_present
    expect(term_score.count_agreed).to eq(4)
    expect(term_score.count_disagreed).to eq(1)
  end

  it "collapses a duplicate user_legislator link onto the surviving one, migrating its score by term" do
    canonical = Legislator.find_by!(external_id: "R000001")
    term_2023 = LegislatorTerm.find_by!(legislator: canonical, term_start_year: 2023)

    expect(UserLegislator.where(id: @dup_user_legislator_loser.id)).not_to exist
    survivor = UserLegislator.find(@dup_user_legislator_survivor.id)
    expect(survivor.legislator_id).to eq(canonical.id)

    term_score = UserLegislatorTermScore.find_by(user_legislator: survivor, legislator_term: term_2023)
    expect(term_score).to be_present
    expect(term_score.count_agreed).to eq(2)
    expect(term_score.count_disagreed).to eq(2)
  end

  it "backfills user_districts from the active user_legislator's active term's district" do
    canonical = Legislator.find_by!(external_id: "R000001")
    survivor = UserLegislator.find(@plain_user_legislator.id)

    expect(survivor.active?).to be(true)
    row = UserDistrict.find_by(user: @plain_user, district_id: canonical.active_term&.district_id)
    expect(row).to be_present
    expect(row.active).to be(true)
  end

  it "makes no external API calls (offline/deterministic)" do
    source = Rails.root.join("db", "data", "20260711000004_convert_duplicate_legislators_to_terms.rb").read
    expect(source).not_to match(/Net::|Faraday|OpenStates|census|httpx|Http\.get/i)
  end

  # repoint_user_legislators only moves an old score when the UserLegislator
  # points at a row that lost the merge. An old score on a link to a
  # never-duplicated legislator -- the vast majority of production rows -- used
  # to be abandoned outright.
  it "migrates a NEVER-duplicated legislator's UserLegislator legacy score into a UserLegislatorTermScore (CR-01)" do
    term = LegislatorTerm.find_by!(legislator: @lone_legislator)

    term_score = UserLegislatorTermScore.find_by(user_legislator: @lone_user_legislator, legislator_term: term)
    expect(term_score).to be_present
    expect(term_score.count_agreed).to eq(6)
    expect(term_score.count_disagreed).to eq(3)
  end

  # @lat: [[legislator-term-conversion-fixture-design#Why find_or_create_by! alone silently lost scores]]
  it "sums both losers' legacy scores when a user is linked to TWO losers within the same duplicate group instead of dropping one (CR-02)" do
    canonical = Legislator.find_by!(external_id: "S000001")
    term_2025 = LegislatorTerm.find_by!(legislator: canonical, term_start_year: 2025)

    # @collision_user_a, the link with the lower id, is repointed in place on
    # the first pass and survives. @collision_user_b, found as its "duplicate"
    # on the second pass, folds into it and is deleted.
    expect(UserLegislator.where(id: @collision_user_b.id)).not_to exist
    survivor = UserLegislator.find(@collision_user_a.id)
    expect(survivor.legislator_id).to eq(canonical.id)

    term_score = UserLegislatorTermScore.find_by(user_legislator: survivor, legislator_term: term_2025)
    expect(term_score).to be_present
    expect(term_score.count_agreed).to eq(7)
    expect(term_score.count_disagreed).to eq(1)
  end
end
