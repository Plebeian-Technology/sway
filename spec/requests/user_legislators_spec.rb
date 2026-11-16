require "rails_helper"

RSpec.describe "UserLegislators", type: :request do
  include ActiveJob::TestHelper

  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /user_legislators" do
    it "renders JSON when signed in" do
      _sway_locale, user = setup
      expect(user).to be_persisted

      get user_legislators_path

      expect(response).to have_http_status(:ok)
    end

    it "redirects unauthenticated visitors" do
      # No setup call — no user signed in, session_hash is empty.
      get user_legislators_path

      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
    end
  end

  describe "POST /user_legislators" do
    it "runs SwayRegistrationService and redirects to legislators when signed in" do
      sway_locale, user = setup
      address = create(:address, city: sway_locale.city, region_code: sway_locale.region_code, country: sway_locale.country)
      create(:user_address, user:, address:)
      expect(user).to be_persisted

      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_return(true)

      post user_legislators_path

      expect(response).to redirect_to(legislators_path)
    end

    it "rejects unauthenticated POSTs" do
      post user_legislators_path

      expect(response).to have_http_status(:unauthorized).or have_http_status(:redirect)
    end

    it "returns JSON 200 with the user's legislators when called with Accept: application/json" do
      sway_locale, user = setup
      address = create(:address, city: sway_locale.city, region_code: sway_locale.region_code, country: sway_locale.country)
      create(:user_address, user:, address:)
      expect(user).to be_persisted

      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_return(true)

      post user_legislators_path, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "resolves a regional locale synchronously via OpenStates without enqueueing a job" do
      _local_locale, user = setup
      regional_locale = create(:sway_locale, :maryland)
      district = create(:district, name: "MD30A", sway_locale: regional_locale)
      legislator = create(:legislator, external_id: "ocd-person/md-30a-delegate", sway_locale: regional_locale, district:)
      seat = Seat.find_or_create_by_identity!(
        district:,
        office_identity: "test-maryland-delegate-30a",
        title: "Delegate",
        chamber: "House of Delegates"
      )
      create(:legislator_term, legislator:, district:, seat:, title: "Delegate", term_start_year: 2023, term_end_year: 2027)

      address = create(
        :address,
        street: "100 State Cir",
        city: "Annapolis",
        region_code: "MD",
        postal_code: "21401",
        country: "United States",
        latitude: 38.9784,
        longitude: -76.4922
      )
      create(:user_address, user:, address:)
      cookies_hash[:sway_locale_id] = regional_locale.id

      stub_request(:get, %r{v3\.openstates\.org/people\.geo})
        .to_return(
          status: 200,
          body: {results: [{id: legislator.external_id, jurisdiction: {name: "Maryland"}}]}.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      clear_enqueued_jobs

      with_env("OPEN_STATES_API_KEY" => "test-open-states-key") do
        post user_legislators_path, headers: {"Accept" => "application/json"}
      end

      expect(response).to have_http_status(:ok)
      expect(enqueued_jobs).to be_empty
      expect(user.user_legislators.where(active: true, legislator:)).to exist
      expect(response.parsed_body.pluck("legislator_id")).to include(legislator.id)
    end

    it "rejects POST when current_sway_locale is not in the user's sway_locales" do
      _sway_locale, user = setup
      foreign_address = create(:address, city: "Austin", region_code: "TX", country: "United States")
      create(:user_address, user:, address: foreign_address)

      expect(SwayRegistrationService).not_to receive(:new)

      post user_legislators_path, headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:forbidden)

      post user_legislators_path
      expect(response).to redirect_to(legislators_path)
      expect(flash[:alert]).to be_present
    end

    context "when resolving representatives raises" do
      def setup_user_with_address
        sway_locale, user = setup
        address = create(:address, city: sway_locale.city, region_code: sway_locale.region_code, country: sway_locale.country)
        create(:user_address, user:, address:)
        user
      end

      it "returns JSON 503 with code registration_unavailable" do
        setup_user_with_address
        allow_any_instance_of(SwayRegistrationService).to receive(:call).and_raise(RuntimeError, "boom")

        post user_legislators_path, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["error"]).to eq(
          "code" => "registration_unavailable",
          "message" => UserLegislatorsController::REPRESENTATIVES_UNAVAILABLE_MESSAGE
        )
      end

      it "redirects HTML to legislators with the alert" do
        setup_user_with_address
        allow_any_instance_of(SwayRegistrationService).to receive(:call).and_raise(RuntimeError, "boom")

        post user_legislators_path

        expect(response).to redirect_to(legislators_path)
        expect(flash[:alert]).to eq(UserLegislatorsController::REPRESENTATIVES_UNAVAILABLE_MESSAGE)
      end

      it "reports the exception to Sentry" do
        setup_user_with_address
        error = RuntimeError.new("boom")
        allow_any_instance_of(SwayRegistrationService).to receive(:call).and_raise(error)
        allow(Sentry).to receive(:capture_exception)

        post user_legislators_path, headers: {"Accept" => "application/json"}

        expect(Sentry).to have_received(:capture_exception).with(error, anything)
      end

      it "handles a geocoding outage the same way" do
        setup_user_with_address
        allow_any_instance_of(SwayRegistrationService).to receive(:call)
          .and_raise(SwayGeocode::ServiceUnavailableError, "down")

        post user_legislators_path, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body.dig("error", "code")).to eq("registration_unavailable")
      end

      it "leaves the user's existing links unchanged" do
        user = setup_user_with_address
        links_before = user.user_legislators.pluck(:id, :legislator_id, :active)
        allow_any_instance_of(SwayRegistrationService).to receive(:call).and_raise(RuntimeError, "boom")

        post user_legislators_path, headers: {"Accept" => "application/json"}

        expect(user.user_legislators.reload.pluck(:id, :legislator_id, :active)).to eq(links_before)
      end

      it "rolls back a link saved before the lookup raised" do
        user = setup_user_with_address
        links_before = user.user_legislators.pluck(:id)
        allow_any_instance_of(SwayRegistrationService).to receive(:call) do
          create(:user_legislator, user:)
          raise "boom"
        end

        post user_legislators_path, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:service_unavailable)
        expect(user.user_legislators.reload.pluck(:id)).to eq(links_before)
      end
    end
  end

  describe "an unexpected error" do
    it "answers 503 onboarding_unavailable to the JSON list and reports the error" do
      setup
      allow(Sentry).to receive(:capture_exception)
      allow(UserLegislatorResource).to receive(:new).and_raise(RuntimeError, "boom")

      get user_legislators_path, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("onboarding_unavailable")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), any_args).once
    end
  end
end
