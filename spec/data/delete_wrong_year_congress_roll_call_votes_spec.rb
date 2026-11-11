# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260804000001_delete_wrong_year_congress_roll_call_votes")

# @lat: [[delete-wrong-year-congress-votes-migration#Why DeleteWrongYearCongressRollCallVotes condemns a whole bill, not single rows]]
RSpec.describe "DeleteWrongYearCongressRollCallVotes data migration", type: :model do
  let(:congress_locale) do
    create(:sway_locale, city: "congress", state: "congress", country: "united_states")
  end
  let(:district) { create(:district, sway_locale: congress_locale) }

  def congress_bill(external_id:, vote_date:, release_days_ago:)
    create(:bill,
      sway_locale: congress_locale,
      legislator: create(:legislator, district: district),
      external_id: external_id,
      senate_vote_date_time_utc: vote_date,
      scheduled_release_date_utc: release_days_ago.days.ago.to_date)
  end

  # A row with its timestamps pinned. update_columns writes them raw, without
  # the touch that would defeat the point.
  def row(bill, source: "congress", inferred: false, created: nil, updated: nil)
    record = create(:legislator_vote,
      bill: bill,
      legislator: create(:legislator, district: district),
      source: source,
      inferred: inferred)
    record.update_columns(created_at: created, updated_at: updated || created) if created
    record
  end

  it "wipes every congress-sourced real row on a bill holding a wrong-year row, clean rows included" do
    bill = congress_bill(external_id: "s1111", vote_date: Time.utc(2024, 6, 18), release_days_ago: 2)
    clean = row(bill, created: Time.utc(2024, 6, 19))
    clobbered = row(bill, created: Time.utc(2024, 6, 19), updated: Time.utc(2026, 7, 24))
    wrong_year = row(bill, created: Time.utc(2026, 7, 24))

    DeleteWrongYearCongressRollCallVotes.new.up

    expect(LegislatorVote.where(id: [clean.id, clobbered.id, wrong_year.id])).to be_empty
  end

  it "keeps manual rows and sponsor-guess rows on a contaminated bill" do
    bill = congress_bill(external_id: "hr192", vote_date: Time.utc(2024, 5, 23), release_days_ago: 3)
    row(bill, created: Time.utc(2026, 7, 24))
    manual = row(bill, source: "manual", created: Time.utc(2026, 7, 24))
    guessed = row(bill, inferred: true, created: Time.utc(2026, 7, 24))

    DeleteWrongYearCongressRollCallVotes.new.up

    expect(LegislatorVote.where(id: manual.id)).to exist
    expect(LegislatorVote.where(id: guessed.id)).to exist
  end

  it "leaves a bill alone when every row sits inside its vote year" do
    bill = congress_bill(external_id: "hr28", vote_date: Time.utc(2025, 1, 14), release_days_ago: 4)
    clean = row(bill, created: Time.utc(2025, 1, 15))
    same_year_update = row(bill, created: Time.utc(2025, 1, 15), updated: Time.utc(2025, 11, 2))

    DeleteWrongYearCongressRollCallVotes.new.up

    expect(LegislatorVote.where(id: [clean.id, same_year_update.id]).count).to eq(2)
  end

  it "leaves a bill alone when it has no chamber vote date to judge against" do
    bill = congress_bill(external_id: "hr86", vote_date: nil, release_days_ago: 5)
    kept = row(bill, created: Time.utc(2026, 7, 24))

    DeleteWrongYearCongressRollCallVotes.new.up

    expect(LegislatorVote.where(id: kept.id)).to exist
  end

  it "never reaches outside the congress locale" do
    baltimore = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
    baltimore_district = create(:district, sway_locale: baltimore)
    bill = create(:bill,
      sway_locale: baltimore,
      legislator: create(:legislator, district: baltimore_district),
      senate_vote_date_time_utc: Time.utc(2024, 6, 18),
      scheduled_release_date_utc: 6.days.ago.to_date)
    kept = create(:legislator_vote,
      bill: bill,
      legislator: create(:legislator, district: baltimore_district),
      source: "congress",
      inferred: false)
    kept.update_columns(created_at: Time.utc(2026, 7, 24), updated_at: Time.utc(2026, 7, 24))

    DeleteWrongYearCongressRollCallVotes.new.up

    expect(LegislatorVote.where(id: kept.id)).to exist
  end

  it "deletes nothing on a second run over the same database" do
    bill = congress_bill(external_id: "pn11-7", vote_date: Time.utc(2025, 1, 24), release_days_ago: 7)
    row(bill, created: Time.utc(2026, 7, 24))

    DeleteWrongYearCongressRollCallVotes.new.up
    expect { DeleteWrongYearCongressRollCallVotes.new.up }.not_to change(LegislatorVote, :count)
  end
end
