# frozen_string_literal: true

require "rails_helper"

RSpec.describe AssignPendingRepresentativesJob do
  # @lat: [[error-reporting-in-tests#Why Sentry's methods are watched rather than the constant replaced]]
  before do
    allow(Sentry).to receive(:capture_exception)
    allow(SwayLogging).to receive(:log_exception)
  end

  let(:congress) { create(:sway_locale, :congress) }
  let(:baltimore) { create(:sway_locale, :baltimore) }

  def pending_user(*sway_locales)
    user = create(:user)
    sway_locales.each { |sway_locale| user.add_pending_representative_locale(sway_locale) }
    user
  end

  def stub_lookup(user, sway_locale, &result)
    service = instance_double(ReconcileUserDistrictsService)
    allow(service).to receive(:call, &result)
    allow(ReconcileUserDistrictsService).to receive(:new).with(user, sway_locale).and_return(service)
    service
  end

  def failing_lookup(user, sway_locale, message)
    stub_lookup(user, sway_locale) { raise SwayGeocode::ServiceUnavailableError, message }
  end

  it "adds the missing links and clears the locale once its lookup succeeds" do
    user = pending_user(congress)
    legislator = create(:legislator, sway_locale: congress)
    stub_lookup(user, congress) { create(:user_legislator, user:, legislator:) }

    described_class.new.perform

    expect(user.user_legislators.where(active: true).pluck(:legislator_id)).to eq([legislator.id])
    expect(user.reload.pending_representative_locale_ids).to eq([])
  end

  it "keeps the locale for a user the lookup still gives no link" do
    user = pending_user(congress)
    stub_lookup(user, congress) { nil }

    described_class.new.perform

    expect(user.reload.pending_representative_locale_ids).to eq([congress.id])
  end

  it "keeps the locale, logs each failed user and moves on while the lookup raises" do
    failing_user = pending_user(congress)
    next_user = pending_user(congress)
    legislator = create(:legislator, sway_locale: congress)
    failing_lookup(failing_user, congress, "Census down")
    next_service = stub_lookup(next_user, congress) { create(:user_legislator, user: next_user, legislator:) }

    expect { described_class.new.perform }.not_to raise_error

    expect(failing_user.reload.pending_representative_locale_ids).to eq([congress.id])
    expect(next_service).to have_received(:call)
    expect(next_user.reload.pending_representative_locale_ids).to eq([])
    expect(SwayLogging).to have_received(:log_exception).with(
      "assign_pending_representatives_job.user_failed",
      exception: instance_of(SwayGeocode::ServiceUnavailableError),
      user_id: failing_user.id,
      sway_locale: congress.name
    )
  end

  it "reports a failing locale to Sentry once per run with the count of failed users" do
    first_user = pending_user(congress, baltimore)
    second_user = pending_user(congress)
    failing_lookup(first_user, congress, "Census down")
    failing_lookup(second_user, congress, "Census down")
    failing_lookup(first_user, baltimore, "Legistar down")

    described_class.new.perform

    expect(Sentry).to have_received(:capture_exception).twice
    expect(Sentry).to have_received(:capture_exception).with(
      an_instance_of(SwayGeocode::ServiceUnavailableError).and(having_attributes(message: "Census down")),
      extra: {sway_locale: congress.name, failed_users: 2}
    ).once
    expect(Sentry).to have_received(:capture_exception).with(
      an_instance_of(SwayGeocode::ServiceUnavailableError).and(having_attributes(message: "Legistar down")),
      extra: {sway_locale: baltimore.name, failed_users: 1}
    ).once
  end

  it "does not look up a user with no pending locale" do
    create(:user)
    allow(ReconcileUserDistrictsService).to receive(:new)

    described_class.new.perform

    expect(ReconcileUserDistrictsService).not_to have_received(:new)
  end
end
