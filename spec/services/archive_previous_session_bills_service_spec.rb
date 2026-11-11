# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ArchivePreviousSessionBillsService" do
  # @type self: ArchivePreviousSessionBillsSpecContext
  include ActiveSupport::Testing::TimeHelpers

  let(:locale) { create(:sway_locale) }
  let!(:session) do
    create(:legislative_session, sway_locale: locale, active: true,
      start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31))
  end
  let(:prior_session) do
    create(:legislative_session, sway_locale: locale,
      start_date: Date.new(2025, 1, 1), end_date: Date.new(2026, 1, 1))
  end
  let(:service) { ArchivePreviousSessionBillsService.new(sway_locale: locale) }
  let!(:old_bill) do
    create(:bill, sway_locale: locale, legislative_session: prior_session,
      introduced_date_time_utc: Time.zone.local(2025, 5, 1), scheduled_release_date_utc: nil)
  end

  before { travel_to Time.zone.local(2026, 2, 1, 12) }

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Eligibility and locale isolation]]
  it "previews only older unscheduled bills in the selected locale" do
    legacy = create(:bill, sway_locale: locale, legislative_session: nil,
      introduced_date_time_utc: Time.zone.local(2025, 8, 1), scheduled_release_date_utc: nil)
    create(:bill, sway_locale: locale, legislative_session: prior_session,
      introduced_date_time_utc: Time.zone.local(2025, 6, 1), scheduled_release_date_utc: Date.new(2025, 9, 1))
    create(:bill, sway_locale: locale, legislative_session: prior_session,
      introduced_date_time_utc: Time.zone.local(2025, 6, 1), scheduled_release_date_utc: Date.new(2026, 3, 1))
    create(:bill, sway_locale: locale, legislative_session: session,
      introduced_date_time_utc: Time.zone.local(2025, 12, 31), scheduled_release_date_utc: nil)
    create(:bill, sway_locale: locale, legislative_session: nil,
      introduced_date_time_utc: session.start_date.beginning_of_day, scheduled_release_date_utc: nil)
    create(:bill, sway_locale: locale, legislative_session: prior_session,
      introduced_date_time_utc: Time.zone.local(2027, 1, 1), scheduled_release_date_utc: nil)
    create(:bill, sway_locale: create(:sway_locale, city: "other_city", state: "maryland", country: "united_states"),
      introduced_date_time_utc: Time.zone.local(2025, 1, 1), scheduled_release_date_utc: nil)

    expect(service.candidates.pluck(:id)).to contain_exactly(old_bill.id, legacy.id)
    expect(old_bill.reload.archived_at).to be_nil
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#History and repeat execution]]
  it "retains votes and scores and archives each eligible bill only once" do
    vote = create(:user_vote, bill: old_bill)
    score_id = old_bill.bill_score.id

    expect { expect(service.call).to eq(1) }.not_to change { Bill.unscoped.count }
    archived = Bill.unscoped.find(old_bill.id)
    timestamp = archived.archived_at
    expect(timestamp).to eq(Time.current)
    expect(vote.reload.bill_id).to eq(old_bill.id)
    expect(archived.bill_score.id).to eq(score_id)
    expect(archived.active).to eq(false)

    travel 1.day
    expect(service.call).to eq(0)
    expect(Bill.unscoped.find(old_bill.id).archived_at).to eq(timestamp)
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Session guards]]
  it "refuses to archive without a current session or before that session starts" do
    session.update!(active: false)
    expect { service.call }.to raise_error(ArgumentError, /active legislative session/)
    session.update!(active: true, start_date: Date.new(2027, 1, 1), end_date: Date.new(2027, 12, 31))
    expect { ArchivePreviousSessionBillsService.new(sway_locale: locale).call }.to raise_error(ArgumentError, /has not started/)
    expect(old_bill.reload.archived_at).to be_nil
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Overlapping and active sessions]]
  it "preserves bills assigned to an overlapping session or another active session" do
    prior_session.update!(end_date: session.start_date + 1.day)
    expect(service.candidates).to be_empty
    prior_session.update!(end_date: Date.new(2025, 12, 31), active: true)
    expect(service.candidates).to be_empty
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Archive query exclusion]]
  it "excludes archives from ordinary queries, associations and direct lookups" do
    old_bill.update!(legislative_session: session)
    old_bill.update!(archived_at: Time.current)
    expect(Bill.current_session(locale)).not_to include(old_bill)
    expect(Bill.all).not_to include(old_bill)
    expect(Bill.where(id: old_bill.id)).to be_empty
    expect(Bill.exists?(old_bill.id)).to eq(false)
    expect { Bill.find(old_bill.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { old_bill.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(locale.bills).not_to include(old_bill)
    expect(session.bills).not_to include(old_bill)
    expect(Bill.unscoped.find(old_bill.id).archived_at).to be_present
    expect(Bill.of_the_month(sway_locale: locale)).to be_nil
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Ingestion preserves the archive]]
  it "skips an archived upstream identity without changing or returning it" do
    service.call
    archived = Bill.unscoped.find(old_bill.id)
    timestamp = archived.archived_at
    summary = archived.summary
    payload = {
      "external_id" => old_bill.external_id,
      "sway_locale_external_id" => locale.name,
      "summary" => "Updated upstream summary",
      "active" => true,
      "archived_at" => nil
    }

    expect {
      expect(LegislationIngestionService.new.upsert_bill_payload(payload)).to be_nil
    }.not_to change { Bill.unscoped.count }
    archived = Bill.unscoped.find(old_bill.id)
    expect(archived.summary).to eq(summary)
    expect(archived.archived_at).to eq(timestamp)
    expect(archived.active).to eq(false)
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Scheduling from a stale record]]
  it "does not restore or schedule an instance loaded before the archive" do
    stale_bill = Bill.find(old_bill.id)
    service.call

    expect { stale_bill.update!(scheduled_release_date_utc: Date.new(2026, 2, 1)) }
      .to raise_error(ActiveRecord::RecordNotSaved)

    archived = Bill.unscoped.find(old_bill.id)
    expect(archived.archived_at).to be_present
    expect(archived.scheduled_release_date_utc).to be_nil
    expect(Bill.of_the_month(sway_locale: locale)).to be_nil
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Stale deletion preserves history]]
  it "refuses to destroy a stale instance or its dependent records after archiving" do
    vote = create(:user_vote, bill: old_bill)
    score_id = old_bill.bill_score.id
    service.call

    expect { old_bill.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(Bill.unscoped.exists?(old_bill.id)).to eq(true)
    expect(UserVote.exists?(vote.id)).to eq(true)
    expect(BillScore.exists?(score_id)).to eq(true)
  end
end
