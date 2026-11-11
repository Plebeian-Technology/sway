# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReconcileUserDistrictsJob do
  # @lat: [[error-reporting-in-tests#Why Sentry's methods are watched rather than the constant replaced]]
  before { allow(Sentry).to receive(:capture_exception) }

  def user_with_address(region_code:, city:)
    user = create(:user)
    address = create(:address, region_code:, city:)
    create(:user_address, user:, address:)
    [user, address]
  end

  def regional_locale_for(address)
    address.sway_locales.find(&:regional?) || raise("regional locale not resolved")
  end

  describe "#perform" do
    it "reconciles every user whose sway_locales include the given locale" do
      user_md1, address_md1 = user_with_address(region_code: "MD", city: "Baltimore")
      user_md2, _address_md2 = user_with_address(region_code: "MD", city: "Annapolis")
      user_ca, _address_ca = user_with_address(region_code: "CA", city: "Los Angeles")
      sway_locale = regional_locale_for(address_md1)

      service_double = instance_double(ReconcileUserDistrictsService, call: nil)
      allow(ReconcileUserDistrictsService).to receive(:new).and_return(service_double)

      described_class.new.perform(sway_locale.id)

      expect(ReconcileUserDistrictsService).to have_received(:new).with(user_md1, sway_locale)
      expect(ReconcileUserDistrictsService).to have_received(:new).with(user_md2, sway_locale)
      expect(ReconcileUserDistrictsService).not_to have_received(:new).with(user_ca, sway_locale)
      expect(service_double).to have_received(:call).twice
    end

    it "isolates a per-user failure — logs + reports to Sentry, continues, never re-raises" do
      user_md1, address_md1 = user_with_address(region_code: "MD", city: "Baltimore")
      user_md2, _address_md2 = user_with_address(region_code: "MD", city: "Annapolis")
      sway_locale = regional_locale_for(address_md1)

      failing_service = instance_double(ReconcileUserDistrictsService)
      allow(failing_service).to receive(:call).and_raise(SwayGeocode::ServiceUnavailableError, "OpenStates down")
      succeeding_service = instance_double(ReconcileUserDistrictsService, call: nil)

      allow(ReconcileUserDistrictsService).to receive(:new)
        .with(user_md1, sway_locale).and_return(failing_service)
      allow(ReconcileUserDistrictsService).to receive(:new)
        .with(user_md2, sway_locale).and_return(succeeding_service)

      expect { described_class.new.perform(sway_locale.id) }.not_to raise_error

      expect(succeeding_service).to have_received(:call)
      expect(Sentry).to have_received(:capture_exception)
        .with(instance_of(SwayGeocode::ServiceUnavailableError), hash_including(extra: {user_id: user_md1.id, sway_locale: sway_locale.name}))
        .once
    end

    it "logs and returns without calling the service when the locale does not exist" do
      allow(ReconcileUserDistrictsService).to receive(:new)

      expect { described_class.new.perform(-1) }.not_to raise_error

      expect(ReconcileUserDistrictsService).not_to have_received(:new)
    end

    it "is idempotent — a repeat perform for the same locale re-diffs without error" do
      _, address_md = user_with_address(region_code: "MD", city: "Baltimore")
      sway_locale = regional_locale_for(address_md)

      service_double = instance_double(ReconcileUserDistrictsService, call: nil)
      allow(ReconcileUserDistrictsService).to receive(:new).and_return(service_double)

      described_class.new.perform(sway_locale.id)
      expect { described_class.new.perform(sway_locale.id) }.not_to raise_error

      expect(service_double).to have_received(:call).twice
    end

    it "captures Seats::UnresolvedSeatError in Sentry when locale-wide district has an unseated term" do
      user, address = user_with_address(region_code: "MD", city: "Baltimore")
      congress = address.sway_locales.find(&:congress?) || raise("congress locale not resolved")
      us0 = create(:district, sway_locale: congress, name: "US0")
      president = create(:legislator, sway_locale: congress)
      unseated_term = create(:legislator_term, legislator: president, district: us0)

      md7 = create(:district, sway_locale: congress, name: "MD7")
      rep = create(:legislator, sway_locale: congress)
      seat = Seat.create!(district: md7, seat_identifier: "md-congress-7", title: "Representative", chamber: "House")
      create(:legislator_term, legislator: rep, district: md7, seat:)

      allow_any_instance_of(Census::Congress).to receive(:request).and_return(
        double(body: {result: {addressMatches: [{geographies: {"118th Congressional Districts" => [{BASENAME: "7"}]}}]}}.to_json)
      )

      described_class.new.perform(congress.id)

      expect(Sentry).to have_received(:capture_exception).with(
        an_instance_of(Seats::UnresolvedSeatError).and(
          having_attributes(message: "Locale-wide term #{unseated_term.id} in #{congress.name} has no persisted seat identity")
        ),
        hash_including(extra: {user_id: user.id, sway_locale: congress.name})
      )
    end
  end
end
