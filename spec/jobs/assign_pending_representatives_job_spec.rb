# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")

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

  context "when the user's typed address was never located" do
    let!(:maryland) { create(:sway_locale, :maryland) }

    def unlocated_pending_user
      allow(Geocoder).to receive(:search).and_return([])
      address = Address.create!(street: "100 N Holliday St", city: "", region_code: "", postal_code: "", country: "")
      user = pending_user(congress)
      UserAddress.create!(user:, address:)
      user
    end

    def senator_seats(user)
      UserLegislator.where(user:, active: true).map(&:legislator).map(&:active_term)
        .select { |term| term.seat.title == "Sen." }
        .map { |term| [term.district.sway_locale.name, term.district.name] }
    end

    before do
      SeedLegislator.run([maryland, congress])
      stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/})
        .to_return(status: 200, body: {features: [{attributes: {"CD#{Census::CURRENT_CONGRESS_NUMBER}" => "07"}}]}.to_json)
      stub_request(:get, %r{v3\.openstates\.org/people\.geo}).to_return(status: 200, body: {results: []}.to_json)
    end

    it "geocodes the address, then assigns the Maryland Senators" do
      user = unlocated_pending_user
      expect(user.address&.located?).to be(false)
      allow(Geocoder).to receive(:search).and_return(
        [Geocoder::Result::Test.new("coordinates" => [39.29105, -76.61069], "state" => "Maryland", "state_code" => "MD", "country_code" => "US")]
      )

      with_env("OPEN_STATES_API_KEY" => "test-open-states-key") { described_class.new.perform }

      expect(user.reload.address).to have_attributes(region_code: "MD", located?: true)
      expect(senator_seats(user)).to eq([[congress.name, "MD0"], [congress.name, "MD0"]])
      expect(user.pending_representative_locale_ids).to eq([])
    end

    it "keeps the locale but still runs the lookups while the geocode still fails" do
      user = unlocated_pending_user
      allow(Geocoder).to receive(:search).and_raise(SocketError, "getaddrinfo failed")
      allow(ReconcileUserDistrictsService).to receive(:new).and_call_original

      described_class.new.perform

      expect(ReconcileUserDistrictsService).to have_received(:new).with(user, congress)
      expect(user.reload.address&.located?).to be(false)
      expect(user.pending_representative_locale_ids).to eq([congress.id])
    end

    it "links the Senators of a typed Maryland address after a seat error at registration while the geocode keeps failing" do
      allow(Geocoder).to receive(:search).and_return([])
      address = Address.create!(street: "100 N Holliday St", city: "Baltimore", region_code: "MD", postal_code: "21202", country: "US")
      user = pending_user(congress)
      UserAddress.create!(user:, address:)
      us0 = congress.districts.find_by!(name: "US0")
      unseated = create(:legislator_term, legislator: create(:legislator, sway_locale: congress), district: us0)
      expect { ReconcileUserDistrictsService.new(user, congress).call }.to raise_error(Seats::UnresolvedSeatError)
      expect(senator_seats(user)).to eq([])
      unseated.destroy!
      allow(Geocoder).to receive(:search).and_raise(SocketError, "getaddrinfo failed")

      described_class.new.perform

      expect(user.reload.address&.located?).to be(false)
      expect(senator_seats(user)).to eq([[congress.name, "MD0"], [congress.name, "MD0"]])
      expect(user.pending_representative_locale_ids).to eq([congress.id])
    end
  end

  it "does not look up a user with no pending locale" do
    create(:user)
    allow(ReconcileUserDistrictsService).to receive(:new)

    described_class.new.perform

    expect(ReconcileUserDistrictsService).not_to have_received(:new)
  end
end
