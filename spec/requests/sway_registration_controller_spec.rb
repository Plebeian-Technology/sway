# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")

RSpec.describe "/registration", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /sway_registration" do
    context "when user is not signed in" do
      it "redirects to root path" do
        get sway_registration_index_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "when user registration is complete" do
      it "redirects to feed path" do
        _sway_locale, user = setup_pre_registration
        create(:user_legislator, user: user)
        user.complete!

        get sway_registration_index_path
        expect(response).to redirect_to(feed_path)
      end
    end

    context "when user registration is pending" do
      it "renders the Registration component" do
        _sway_locale, _user = setup_pre_registration

        get sway_registration_index_path
        expect(inertia).to render_component Pages::REGISTRATION
      end

      it "renders without the processing prop" do
        _sway_locale, _user = setup_pre_registration

        get sway_registration_index_path
        expect(inertia).to have_no_prop(:processing)
      end
    end

    context "when user registration is processing" do
      it "renders the Registration component with processing prop" do
        _sway_locale, user = setup_pre_registration
        user.start_processing!

        get sway_registration_index_path
        expect(inertia).to render_component Pages::REGISTRATION
        expect(inertia).to have_props(processing: true)
      end
    end
  end

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
  describe "POST /sway_registration format negotiation" do
    it "returns the JSON envelope for a bearer request even without an Accept header" do
      # Nobody is signed in, so #create takes its current_user.nil? branch and
      # calls respond_json_or_redirect(status: :unauthorized, ...). The bearer
      # header on its own must be enough to pick the JSON branch; this used to
      # answer with a 302 redirect instead.
      post "/sway_registration",
        params: {},
        headers: {"Authorization" => "Bearer not-a-real-token"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthorized")
    end

    it "returns the JSON envelope for a legacy Token authorization header" do
      post "/sway_registration",
        params: {},
        headers: {"Authorization" => "Token not-a-real-token"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthorized")
    end
  end

  describe "POST /sway_registration when a geocoding service is unavailable" do
    let!(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "MD", country: "US") }
    let!(:district) { create(:district, sway_locale: sway_locale) }
    let!(:legislator) { create(:legislator, district: district) }
    let!(:user) do
      create(:user, is_registration_complete: false, registration_status: "pending")
    end

    let(:address_params) do
      {
        sway_registration: {
          street: "100 N Holliday St",
          street2: "",
          city: "Baltimore",
          region_code: "MD",
          postal_code: "21202",
          country: "US",
          latitude: 39.29105,
          longitude: -76.61069
        }
      }
    end

    before do
      sign_in(user)
      # Avoid real geocoding when Address#sway_locales resolves city/state/congress.
      allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
      allow(Sentry).to receive(:capture_exception)
    end

    it "skips the unavailable locale and completes with the locales that resolved (JSON)" do
      call_count = 0
      allow_any_instance_of(SwayRegistrationService).to receive(:call) do # rubocop:disable RSpec/AnyInstance
        call_count += 1
        raise SwayGeocode::ServiceUnavailableError, "Census TIGERweb geocoding is unavailable" if call_count > 1

        UserLegislator.find_or_create_by!(user: user, legislator: legislator)
      end

      post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("error", "code")).not_to eq("geocoding_unavailable")
      expect(response.parsed_body["registration_status"]).to eq("completed")
      expect(user.reload.registration_status).to eq("completed")
      expect(Sentry).to have_received(:capture_exception)
        .with(an_instance_of(SwayGeocode::ServiceUnavailableError), extra: hash_including(user_id: user.id))
        .twice
    end

    it "keeps none of a failing locale's own links and keeps the links of a locale that resolved earlier" do
      failing_legislator = create(:legislator, district: district)
      call_count = 0
      allow_any_instance_of(SwayRegistrationService).to receive(:call) do # rubocop:disable RSpec/AnyInstance
        call_count += 1
        if call_count == 1
          UserLegislator.find_or_create_by!(user: user, legislator: legislator)
        else
          UserLegislator.find_or_create_by!(user: user, legislator: failing_legislator)
          raise SwayGeocode::ServiceUnavailableError, "OpenStates geocoding is unavailable"
        end
      end

      post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(UserLegislator.find_by!(user: user, legislator: legislator).active).to be(true)
      expect(UserLegislator.where(user: user, legislator: failing_legislator)).to be_empty
      expect(user.reload.registration_status).to eq("completed")
    end

    it "follows the normal completion redirect with no flash alert (web)" do
      call_count = 0
      allow_any_instance_of(SwayRegistrationService).to receive(:call) do # rubocop:disable RSpec/AnyInstance
        call_count += 1
        raise SwayGeocode::ServiceUnavailableError, "Census TIGERweb geocoding is unavailable" if call_count > 1

        UserLegislator.find_or_create_by!(user: user, legislator: legislator)
      end

      post "/sway_registration", params: address_params

      expect(response).to redirect_to(feed_path)
      expect(flash[:alert]).to be_nil
    end
  end

  describe "POST /sway_registration when one locale's representative lookup fails" do
    let!(:baltimore) { create(:sway_locale, :baltimore) }
    let!(:maryland) { create(:sway_locale, :maryland) }
    let!(:congress) { create(:sway_locale, :congress) }
    let!(:mayor) do
      create_titled_seat_term(
        district: create(:district, sway_locale: baltimore, name: "MD0"),
        seat_identifier: "baltimore-mayor",
        title: "Mayor",
        years: [2024, 2028]
      )
    end
    let!(:house_member) do
      create_titled_seat_term(
        district: create(:district, sway_locale: congress, name: "MD7"),
        seat_identifier: "md-house-district-7",
        title: "Representative",
        years: [2025, 2027]
      )
    end
    let!(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }
    let(:address_params) do
      {
        sway_registration: {
          street: "100 N Holliday St",
          city: "Baltimore",
          region_code: "MD",
          postal_code: "21202",
          country: "US",
          latitude: 39.29105,
          longitude: -76.61069
        }
      }
    end

    def create_titled_seat_term(district:, seat_identifier:, title:, years:)
      seat = Seat.create!(district:, seat_identifier:, title:, chamber: title)
      legislator = create(:legislator, district:)
      create(
        :legislator_term,
        legislator:,
        district:,
        seat:,
        title:,
        term_start_year: years[0],
        term_end_year: years[1]
      )
      legislator
    end

    def stub_census_body(body)
      stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/})
        .to_return(status: 200, body:)
    end

    def active_legislator_ids
      UserLegislator.where(user:, active: true).pluck(:legislator_id)
    end

    before do
      sign_in(user)
      allow(Sentry).to receive(:capture_exception)
      stub_census_body("not json")
    end

    it "completes with the locales that resolved and reports the failing one (JSON)" do
      post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["registration_status"]).to eq("completed")
      expect(active_legislator_ids).to eq([mayor.id])
      expect(UserLegislator.where(user:, legislator: house_member)).to be_empty
      expect(user.reload.registration_status).to eq("completed")
      expect(Sentry).to have_received(:capture_exception)
        .with(an_instance_of(SwayGeocode::ServiceUnavailableError), level: :warning)
    end

    it "follows the normal completion redirect with no flash alert (web)" do
      post "/sway_registration", params: address_params

      expect(response).to redirect_to(feed_path)
      expect(flash[:alert]).to be_nil
      expect(active_legislator_ids).to eq([mayor.id])
    end

    it "answers a bearer request without an Accept header with the JSON completion body" do
      post "/sway_registration", params: address_params, headers: authenticate_as(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"ok" => true, "registration_status" => "completed"})
      expect(active_legislator_ids).to eq([mayor.id])
    end

    it "skips Maryland when OpenStates answers HTTP 500 and completes with the Baltimore links" do
      stub_census_body({features: [{attributes: {"CD#{Census::CURRENT_CONGRESS_NUMBER}" => "07"}}]}.to_json)
      create_titled_seat_term(
        district: create(:district, sway_locale: maryland, name: "MD46"),
        seat_identifier: "md-senate-district-46",
        title: "Senator",
        years: [2023, 2027]
      )
      stub_request(:get, %r{v3\.openstates\.org/people\.geo}).to_return(status: 500, body: "")

      with_env("OPEN_STATES_API_KEY" => "test-open-states-key") do
        post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}
      end

      expect(response).to have_http_status(:ok)
      expect(active_legislator_ids).to contain_exactly(mayor.id, house_member.id)
      expect(Sentry).to have_received(:capture_exception).with(
        an_instance_of(SwayGeocode::ServiceUnavailableError),
        extra: hash_including(user_id: user.id, sway_locale: maryland.name)
      )
    end

    it "reports every locale and completes with every locale waiting when every locale is skipped" do
      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_raise( # rubocop:disable RSpec/AnyInstance
        SwayGeocode::ServiceUnavailableError,
        "geocoding is unavailable"
      )

      allow(Sentry).to receive(:capture_message)

      post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["registration_status"]).to eq("completed")
      expect(UserLegislator.where(user:)).to be_empty
      expect(user.reload.pending_representative_locale_ids).to contain_exactly(baltimore.id, maryland.id, congress.id)
      expect(Sentry).not_to have_received(:capture_message)
      [baltimore, maryland, congress].each do |sway_locale|
        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(SwayGeocode::ServiceUnavailableError),
          extra: hash_including(sway_locale: sway_locale.name)
        )
      end
    end

    describe "recording the locales to assign later" do
      def post_with_every_lookup_answering
        stub_census_body({features: [{attributes: {"CD#{Census::CURRENT_CONGRESS_NUMBER}" => "07"}}]}.to_json)
        stub_request(:get, %r{v3\.openstates\.org/people\.geo}).to_return(status: 200, body: {results: []}.to_json)
        with_env("OPEN_STATES_API_KEY" => "test-open-states-key") do
          post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}
        end
      end

      it "records the locale whose lookup failed and not the locale that resolved" do
        post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(active_legislator_ids).to eq([mayor.id])
        expect(user.reload.pending_representative_locale_ids).to include(congress.id)
        expect(user.pending_representative_locale_ids).not_to include(baltimore.id)
      end

      it "records nothing when every lookup answers and no term is skipped" do
        post_with_every_lookup_answering

        expect(response).to have_http_status(:ok)
        expect(active_legislator_ids).to contain_exactly(mayor.id, house_member.id)
        expect(user.reload.pending_representative_locale_ids).to eq([])
      end

      it "records the locale of a term whose seat cannot be resolved" do
        md0 = District.find_by!(sway_locale: baltimore, name: "MD0")
        create(
          :legislator_term,
          legislator: create(:legislator, district: md0),
          district: md0,
          seat: nil,
          title: nil,
          term_start_year: 2024,
          term_end_year: 2028
        )

        post_with_every_lookup_answering

        expect(response).to have_http_status(:ok)
        expect(active_legislator_ids).to contain_exactly(mayor.id, house_member.id)
        expect(user.reload.pending_representative_locale_ids).to eq([baltimore.id])
        expect(Sentry).to have_received(:capture_exception)
          .with(an_instance_of(Seats::UnresolvedSeatError), level: :warning)
      end

      it "keeps one copy of a locale id that a second registration skips again" do
        user.update!(pending_representative_locale_ids: [congress.id])

        post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(user.reload.pending_representative_locale_ids.count(congress.id)).to eq(1)
      end
    end

    describe "when a user waiting for representatives submits a different address" do
      before do
        UserAddress.create!(user:, address: create(:address, street: "1 Old Saved Rd"))
        user.add_pending_representative_locale(congress)
        user.update_columns(registration_status: "completed", is_registration_complete: true)
      end

      it "replaces the address and looks the new one up without asking to confirm a switch" do
        post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["registration_status"]).to eq("completed")
        expect(response.parsed_body.dig("error", "code")).to be_nil
        expect(user.reload.address.street).to eq("100 N Holliday St")
        expect(active_legislator_ids).to eq([mayor.id])
      end

      it "still asks a user with an active legislator link to confirm the switch" do
        linked_user = create(:user, :registered)
        linked_address = create(:address, street: "2 Old Saved Rd")
        UserAddress.create!(user: linked_user, address: linked_address)
        linked_user.add_pending_representative_locale(congress)
        sign_in(linked_user)

        post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "code")).to eq("confirmation_required")
        expect(linked_user.reload.address).to eq(linked_address)
      end
    end
  end

  describe "POST /sway_registration when no Sway locale resolves the address" do
    let!(:congress) { create(:sway_locale, :congress) }
    let!(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }
    let(:toronto_params) do
      {
        sway_registration: {
          street: "100 Queen St W",
          city: "Toronto",
          region_code: "ON",
          postal_code: "M5H 2N2",
          country: "Canada",
          latitude: 43.65323,
          longitude: -79.38318
        }
      }
    end

    def create_us_president
      us_district = create(:district, sway_locale: congress, name: "US0")
      seat = Seat.create!(district: us_district, seat_identifier: "us-president", title: "President", chamber: "White House")
      legislator = create(:legislator, district: us_district)
      create(:legislator_term, legislator:, district: us_district, seat:, term_start_year: 2025, term_end_year: 2029)
      legislator
    end

    before do
      sign_in(user)
      allow(Sentry).to receive(:capture_message)
    end

    it "completes a user outside the United States with the President as the only link (JSON)" do
      president = create_us_president

      post "/sway_registration", params: toronto_params, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["registration_status"]).to eq("completed")
      expect(UserLegislator.where(user:, active: true).pluck(:legislator_id)).to eq([president.id])
      expect(user.reload.pending_representative_locale_ids).to eq([])
      expect(Sentry).not_to have_received(:capture_message)
    end

    context "when no current President term exists" do
      it "completes the user with the Congress locale waiting and reports it (JSON)" do
        post "/sway_registration", params: toronto_params, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["registration_status"]).to eq("completed")
        expect(response.parsed_body.dig("error", "code")).to be_nil
        expect(user.reload.registration_status).to eq("completed")
        expect(user.is_registration_complete).to be(true)
        expect(user.pending_representative_locale_ids).to eq([congress.id])
        expect(UserLegislator.where(user:)).to be_empty
        expect(Sentry).to have_received(:capture_message).once.with(
          "sway_registration.no_representatives_resolved",
          level: :warning,
          extra: hash_including(user_id: user.id, sway_locales: include(congress.name))
        )
      end

      it "redirects a browser to the feed" do
        post "/sway_registration", params: toronto_params

        expect(response).to redirect_to(feed_path)
        expect(user.reload.registration_status).to eq("completed")
        expect(user.pending_representative_locale_ids).to eq([congress.id])
      end
    end
  end

  # @lat: [[identity-and-access#Two voter-registration flags mean different things]]
  describe "POST /sway_registration voter-registration address confirmation" do
    let!(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "MD", country: "US") }
    let!(:district) { create(:district, sway_locale: sway_locale) }
    let!(:legislator) { create(:legislator, district: district) }
    let!(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }

    let(:address_params) do
      {
        street: "100 N Holliday St",
        street2: "",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US",
        latitude: 39.29105,
        longitude: -76.61069
      }
    end

    before do
      sign_in(user)
      UserLegislator.find_or_create_by!(user: user, legislator: legislator)
    end

    it "stores true on the user when the confirmation checkbox is ticked" do
      post "/sway_registration",
        params: {sway_registration: address_params.merge(is_voter_registration_address_confirmed: true)},
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(user.reload.is_voter_registration_address_confirmed).to be(true)
    end

    it "still registers successfully and stores false when the field is omitted entirely" do
      post "/sway_registration", params: {sway_registration: address_params}, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(user.reload.registration_status).to eq("completed")
      expect(user.is_voter_registration_address_confirmed).to be(false)
    end

    context "when the user row fails a validation added after it was saved" do
      before { user.update_column(:full_name, "Zoe 9") }

      it "stores the ticked confirmation and completes registration" do
        post "/sway_registration",
          params: {sway_registration: address_params.merge(is_voter_registration_address_confirmed: true)},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(user.reload.is_voter_registration_address_confirmed).to be(true)
        expect(user.registration_status).to eq("completed")
      end

      it "stores false when the field is omitted" do
        user.update_column(:is_voter_registration_address_confirmed, true)

        post "/sway_registration", params: {sway_registration: address_params}, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(user.reload.is_voter_registration_address_confirmed).to be(false)
        expect(user.registration_status).to eq("completed")
      end

      it "completes a first registration that resolves representatives" do
        UserLegislator.where(user: user).delete_all
        allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
        allow_any_instance_of(SwayRegistrationService).to receive(:call) do # rubocop:disable RSpec/AnyInstance
          UserLegislator.find_or_create_by!(user: user, legislator: legislator)
        end

        post "/sway_registration", params: {sway_registration: address_params}, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(user.reload.registration_status).to eq("completed")
        expect(user.is_registration_complete).to be(true)
      end

      it "switches a completed registration to a new address" do
        user.update_columns(registration_status: "completed", is_registration_complete: true)
        create(:user_address, user: user, address: create(:address))
        allow_any_instance_of(UserAddressSwitchService).to receive(:call).and_return(true) # rubocop:disable RSpec/AnyInstance

        post "/sway_registration",
          params: {sway_registration: address_params.merge(confirm_deactivate_legislators: true)},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(user.reload.registration_status).to eq("completed")
      end
    end
  end

  # @lat: [[address-place-classification#Why an empty list is not a rejection]]
  describe "POST /sway_registration place classification" do
    let(:user) { create(:user) }
    let(:legislator) { create(:legislator) }
    let(:address_params) do
      {
        street: "100 N Holliday St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US",
        latitude: 39.29105,
        longitude: -76.61069
      }
    end

    before do
      sign_in(user)
      UserLegislator.find_or_create_by!(user: user, legislator: legislator)
    end

    it "stores the place types a registration posts" do
      post "/sway_registration",
        params: {sway_registration: address_params.merge(place_types: ["premise", "street_address"])},
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(user.reload.address.place_types).to eq(["premise", "street_address"])
    end

    it "still succeeds and stores nothing when the field is omitted" do
      post "/sway_registration", params: {sway_registration: address_params}, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(user.reload.address.place_types).to eq([])
    end

    it "does not make a second address row for the same building with different place types and preserves existing place_types" do
      post "/sway_registration",
        params: {sway_registration: address_params.merge(place_types: ["premise"])},
        headers: {"Accept" => "application/json"}
      expect {
        post "/sway_registration",
          params: {sway_registration: address_params.merge(place_types: ["establishment"])},
          headers: {"Accept" => "application/json"}
      }.not_to change(Address, :count)
      expect(user.reload.address.place_types).to eq(["premise"])
    end
  end

  # @lat: [[identity-and-access#A user holds one address]]
  describe "POST /sway_registration when the same user registers again" do
    let(:user) { create(:user) }
    let(:legislator) { create(:legislator) }
    let(:base_params) do
      {
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US"
      }
    end

    def register_address(street:, latitude:, longitude:)
      post "/sway_registration",
        params: {sway_registration: base_params.merge(street:, latitude:, longitude:)},
        headers: {"Accept" => "application/json"}
    end

    before do
      sign_in(user)
      UserLegislator.find_or_create_by!(user: user, legislator: legislator)
    end

    it "leaves one join row, pointing at the address just submitted" do
      sway_locale = legislator.sway_locale
      old_district = create(:district, sway_locale: sway_locale)
      create(:legislator_term, legislator: legislator, district: old_district)
      allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_return([legislator]) # rubocop:disable RSpec/AnyInstance

      register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)
      first_address = user.reload.address

      post "/sway_registration",
        params: {
          sway_registration: base_params.merge(
            street: "100 Light St",
            latitude: 39.2851,
            longitude: -76.6141,
            confirm_deactivate_legislators: true
          )
        },
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(UserAddress.where(user: user).count).to eq(1)
      expect(user.reload.address.id).not_to eq(first_address.id)
      expect(user.address.street).to eq("100 Light St")
    end

    it "adds no join row when the same address is submitted twice, even with confirm_deactivate_legislators: true" do
      register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)

      expect {
        register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)
      }.to change(UserAddress, :count).by(0).and change(UserAddressChange, :count).by(0)

      expect {
        post "/sway_registration",
          params: {
            sway_registration: base_params.merge(
              street: "100 N Holliday St",
              latitude: 39.29105,
              longitude: -76.61069,
              confirm_deactivate_legislators: true
            )
          },
          headers: {"Accept" => "application/json"}
      }.to change(UserAddress, :count).by(0).and change(UserAddressChange, :count).by(0)

      expect(response).to have_http_status(:ok)
      expect(user.user_legislators.where(active: true).count).to eq(1)
    end

    describe "when a concurrent request stored the link first" do
      def city_hall_address_id
        Address.find_by!(normalized_key: Address.normalized_key_for(latitude: 39.29105, longitude: -76.61069)).id
      end

      before do
        allow_any_instance_of(User).to receive(:user_address).and_return(nil) # rubocop:disable RSpec/AnyInstance
      end

      it "answers 200 with one link to the submitted address when the uniqueness validation refuses the insert" do
        UserAddress.create!(user:, address: create(:address, street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069))
        register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)

        expect(response).to have_http_status(:ok)
        expect(UserAddress.where(user:).pluck(:address_id)).to eq([city_hall_address_id])
      end

      it "answers 200 with one link to the submitted address when the unique index refuses the insert" do
        UserAddress.create!(user:, address: create(:address, street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069))
        allow(UserAddress).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)

        expect(response).to have_http_status(:ok)
        expect(UserAddress.where(user:).pluck(:address_id)).to eq([city_hall_address_id])
      end

      it "updates the stored link to the submitted address, as a sequential repeat does, when the other request stored a different address" do
        UserAddress.create!(user:, address: create(:address, street: "100 Light St", latitude: 39.2851, longitude: -76.6141))

        register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)

        expect(response).to have_http_status(:ok)
        expect(UserAddress.where(user:).pluck(:address_id)).to eq([city_hall_address_id])
      end
    end

    it "returns 422 confirmation_required without changing address or deactivating legislators when confirm_deactivate_legislators is false or omitted" do
      register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)
      first_address = user.reload.address

      post "/sway_registration",
        params: {
          sway_registration: base_params.merge(
            street: "100 Light St",
            latitude: 39.2851,
            longitude: -76.6141,
            confirm_deactivate_legislators: false
          )
        },
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("confirmation_required")
      expect(user.reload.address).to eq(first_address)
      expect(user.user_legislators.where(active: true).count).to eq(1)

      post "/sway_registration",
        params: {
          sway_registration: base_params.merge(
            street: "100 Light St",
            latitude: 39.2851,
            longitude: -76.6141
          )
        },
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("confirmation_required")
      expect(user.reload.address).to eq(first_address)
      expect(user.user_legislators.where(active: true).count).to eq(1)
      expect(UserAddressChange.count).to eq(0)
    end

    it "returns 422 address_switch_cooldown when the user switched addresses within the cooldown period" do
      register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)
      first_address = user.reload.address
      prior_address = create(:address, street: "1 E Pratt St")
      create(
        :user_address_change,
        user: user,
        previous_address: prior_address,
        new_address: first_address,
        created_at: 2.days.ago
      )

      post "/sway_registration",
        params: {
          sway_registration: base_params.merge(
            street: "100 Light St",
            latitude: 39.2851,
            longitude: -76.6141,
            confirm_deactivate_legislators: true
          )
        },
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("address_switch_cooldown")
      expect(user.reload.address).to eq(first_address)
      expect(user.user_legislators.where(active: true).count).to eq(1)
    end

    it "deactivates previous user_legislators and re-runs registration when confirm_deactivate_legislators is true" do
      sway_locale = legislator.sway_locale
      old_district = create(:district, sway_locale: sway_locale, name: "MD1")
      create(:legislator_term, legislator: legislator, district: old_district)
      create(:user_district, user: user, district: old_district, active: true)
      bill = create(:bill, sway_locale: sway_locale, legislator: legislator)
      create(:user_vote, user: user, bill: bill, support: LegislatorVote::Support::FOR)

      new_district = create(:district, sway_locale: sway_locale, name: "MD2")
      new_legislator = create(:legislator, district: new_district, sway_locale: sway_locale)
      create(:legislator_term, legislator: new_legislator, district: new_district)
      allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_return([new_legislator]) # rubocop:disable RSpec/AnyInstance

      register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)
      first_address = user.reload.address

      expect {
        post "/sway_registration",
          params: {
            sway_registration: base_params.merge(
              street: "100 Light St",
              latitude: 39.2851,
              longitude: -76.6141,
              confirm_deactivate_legislators: true
            )
          },
          headers: {"Accept" => "application/json"}
      }.to change(UserAddressChange, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(user.user_legislators.find_by(legislator: legislator).active).to be(false)
      expect(user.user_districts.find_by(district: old_district).active).to be(false)
      expect(user.user_legislators.find_by(legislator: new_legislator).active).to be(true)
      expect(user.user_districts.find_by(district: new_district).active).to be(true)

      change = UserAddressChange.find_by!(user: user)
      expect(change.previous_address_id).to eq(first_address.id)
      expect(change.new_address_id).to eq(user.reload.address.id)
      expect(change.deactivated_legislator_ids).to eq([legislator.id])
      expect(change.activated_legislator_ids).to eq([new_legislator.id])
      expect(change.prior_vote_count).to eq(1)
      expect(change.prior_voted_bill_ids).to eq([bill.id])
    end

    it "preserves previous address and active legislators when confirmed switch resolves zero representatives" do
      sway_locale = legislator.sway_locale
      allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_return([]) # rubocop:disable RSpec/AnyInstance

      register_address(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)
      first_address = user.reload.address

      post "/sway_registration",
        params: {
          sway_registration: base_params.merge(
            street: "100 Light St",
            latitude: 39.2851,
            longitude: -76.6141,
            confirm_deactivate_legislators: true
          )
        },
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("no_representatives")
      expect(user.reload.address).to eq(first_address)
      expect(user.user_legislators.find_by(legislator: legislator).active).to be(true)
      expect(UserAddressChange.count).to eq(0)
    end
  end

  describe "POST /sway_registration when a confirmed address switch fails to resolve" do
    let!(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "MD", country: "US") }
    let!(:legislator) { create(:legislator, sway_locale: sway_locale) }
    let!(:user) { complete_registration_with_active_link(create(:user), legislator: legislator) }
    let!(:address_before_switch) { create(:address, street: "100 N Holliday St", city: "Baltimore", region_code: "MD", postal_code: "21202") }
    let(:address_switch_params) do
      {
        sway_registration: {
          street: "100 Light St",
          city: "Baltimore",
          region_code: "MD",
          postal_code: "21202",
          country: "US",
          latitude: 39.2851,
          longitude: -76.6141,
          confirm_deactivate_legislators: true
        }
      }
    end

    before do
      UserAddress.create!(user: user, address: address_before_switch)
      sign_in(user)
      allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
      allow(Sentry).to receive(:capture_exception)
    end

    it "answers 503 registration_unavailable and changes nothing (JSON)" do
      error = RuntimeError.new("unexpected resolution failure")
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_raise(error) # rubocop:disable RSpec/AnyInstance

      expect {
        post "/sway_registration", params: address_switch_params, headers: {"Accept" => "application/json"}
      }.not_to change(UserAddressChange, :count)

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to eq(
        "code" => "registration_unavailable",
        "message" => SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_UNAVAILABLE_MESSAGE
      )
      expect(user.reload.address).to eq(address_before_switch)
      expect(UserLegislator.find_by!(user: user, legislator: legislator).active).to be(true)
      expect(Sentry).to have_received(:capture_exception)
        .with(error, extra: {user_id: user.id, address_id: Address.order(:id).last&.id})
    end

    it "redirects back to registration with the switch alert (web)" do
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_raise(RuntimeError, "unexpected resolution failure") # rubocop:disable RSpec/AnyInstance

      post "/sway_registration", params: address_switch_params

      expect(response).to redirect_to(sway_registration_index_path)
      expect(flash[:alert]).to eq(SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_UNAVAILABLE_MESSAGE)
      expect(user.reload.address).to eq(address_before_switch)
      expect(UserLegislator.find_by!(user: user, legislator: legislator).active).to be(true)
    end

    it "still answers geocoding_unavailable when a geocoding service is down" do
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_raise(SwayGeocode::ServiceUnavailableError, "Census TIGERweb geocoding is unavailable") # rubocop:disable RSpec/AnyInstance

      post "/sway_registration", params: address_switch_params, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("geocoding_unavailable")
      expect(user.reload.address).to eq(address_before_switch)
      expect(Sentry).not_to have_received(:capture_exception)
    end
  end

  # @lat: [[address-normalized-key#Finding an address during registration]]
  describe "POST /sway_registration address de-duplication" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:legislator) { create(:legislator) }
    let(:base_params) do
      {
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US",
        latitude: 39.29105,
        longitude: -76.61069
      }
    end

    before do
      UserLegislator.find_or_create_by!(user: user, legislator: legislator)
      UserLegislator.find_or_create_by!(user: other_user, legislator: legislator)
    end

    it "reaches one address row for two spellings of one building" do
      sign_in(user)
      post "/sway_registration",
        params: {sway_registration: base_params.merge(street: "100 N Holliday St")},
        headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)

      sign_in(other_user)
      expect {
        post "/sway_registration",
          params: {sway_registration: base_params.merge(street: "100 N Holliday Street")},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
      }.not_to change(Address, :count)
    end

    it "stores the key on the row it creates" do
      sign_in(user)
      post "/sway_registration",
        params: {sway_registration: base_params.merge(street: "100 N Holliday St")},
        headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)

      address = user.reload.address
      expect(address.normalized_key).to eq(address.computed_normalized_key)
      expect(address.normalized_key).to be_present
    end

    it "keeps two different buildings apart" do
      sign_in(user)
      post "/sway_registration",
        params: {sway_registration: base_params.merge(street: "100 N Holliday St")},
        headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)

      sign_in(other_user)
      expect {
        post "/sway_registration",
          params: {sway_registration: base_params.merge(street: "100 Light St", latitude: 39.2851, longitude: -76.6141)},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
      }.to change(Address, :count).by(1)
    end

    it "keeps two different apartment units at the same coordinates in separate address rows" do
      sign_in(user)
      post "/sway_registration",
        params: {sway_registration: base_params.merge(street: "100 N Holliday St", street2: "Apt 1A")},
        headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)

      sign_in(other_user)
      expect {
        post "/sway_registration",
          params: {sway_registration: base_params.merge(street: "100 N Holliday St", street2: "Apt 2B")},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
      }.to change(Address, :count).by(1)

      expect(user.reload.address.id).not_to eq(other_user.reload.address.id)
      expect(user.address.street2).to eq("Apt 1A")
      expect(other_user.address.street2).to eq("Apt 2B")
    end
  end

  # @lat: [[low-friction-voting#Reconciliation on registration and sign-in]]
  describe "POST /sway_registration with pending vote reconciliation" do
    let!(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "MD", country: "US") }
    let!(:district) { create(:district, sway_locale: sway_locale) }
    let!(:legislator) { create(:legislator, district: district) }
    let!(:bill) { create(:bill, sway_locale: sway_locale) }
    let!(:reg_user) { create(:user, is_registration_complete: false, registration_status: "pending") }

    let(:address_params) do
      {
        street: "100 N Holliday St",
        street2: "",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US",
        latitude: 39.29105,
        longitude: -76.61069
      }
    end

    before do
      sign_in(reg_user)
      allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
      allow_any_instance_of(SwayRegistrationService).to receive(:call) do # rubocop:disable RSpec/AnyInstance
        UserLegislator.find_or_create_by!(user: reg_user, legislator: legislator)
        reg_user.complete!
      end
    end

    it "reconciles pending vote and redirects to bill_path" do
      post provisional_votes_path, params: {bill_id: bill.id, support: "FOR"}

      expect {
        post "/sway_registration", params: {sway_registration: address_params}
      }.to change(UserVote, :count).by(1)

      expect(response).to redirect_to(bill_path(bill))
      expect(response.cookies["sway_pending_vote"]).to be_nil
      expect(UserVote.find_by(user: reg_user, bill: bill).support).to eq("FOR")
    end

    it "redirects to feed_path when no pending vote cookie exists" do
      post "/sway_registration", params: {sway_registration: address_params}

      expect(response).to redirect_to(feed_path)
    end
  end

  # @lat: [[address-normalized-key#Finding an address during registration]]
  describe "POST /sway_registration with an incomplete or malformed address" do
    let(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }
    let(:json_headers) { {"Accept" => "application/json"} }
    let(:complete_params) do
      {
        street: "100 N Holliday St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US",
        latitude: 39.29105,
        longitude: -76.61069
      }
    end

    before do
      sign_in(user)
      allow(Geocoder).to receive(:search).and_return([])
    end

    def post_json_body(body)
      post "/sway_registration",
        params: body.to_json,
        headers: json_headers.merge("Content-Type" => "application/json")
    end

    def expect_neither_400_nor_500
      expect(response).not_to have_http_status(:bad_request)
      expect(response).not_to have_http_status(:internal_server_error)
    end

    def stored_address_for(user)
      expect(UserAddress.where(user: user).count).to eq(1)
      user.reload.address
    end

    def expect_one_stored_address_for(user)
      expect_neither_400_nor_500
      stored_address_for(user)
    end

    def expect_blank_address(address)
      expect(address).to have_attributes(
        street: "", city: "", region_code: "", postal_code: "", country: "",
        latitude: nil, longitude: nil, normalized_key: nil
      )
    end

    context "when the body carries no address" do
      [
        ["no sway_registration key is sent", {}],
        ["sway_registration is an empty object", {sway_registration: {}}],
        ["sway_registration is JSON null", {sway_registration: nil}],
        ["sway_registration is a plain string", {sway_registration: "abc"}]
      ].each do |shape, body|
        it "stores one blank address and answers neither 400 nor 500 when #{shape}" do
          expect { post_json_body(body) }.to change(Address, :count).by(1)

          expect_blank_address(expect_one_stored_address_for(user))
        end
      end

      it "redirects a browser that posts an empty object instead of answering 400" do
        post "/sway_registration", params: {sway_registration: {}}

        expect(response).to have_http_status(:redirect)
        expect_blank_address(stored_address_for(user))
      end
    end

    it "stores a null street as blank and the other fields as sent" do
      post_json_body({sway_registration: complete_params.merge(street: nil)})

      expect(expect_one_stored_address_for(user)).to have_attributes(
        street: "", city: "Baltimore", region_code: "MD", postal_code: "21202", country: "US",
        latitude: "39.29105", longitude: "-76.61069"
      )
    end

    it "stores blank and whitespace text fields as given" do
      post_json_body({sway_registration: complete_params.merge(street: "", street2: " ", city: "  ", postal_code: " ")})

      expect(expect_one_stored_address_for(user)).to have_attributes(
        street: "", street2: " ", city: "  ", region_code: "MD", postal_code: " ", country: "US"
      )
    end

    it "answers neither 400 nor 500 when the address has no region and no country" do
      post "/sway_registration", params: {}, headers: json_headers

      expect_neither_400_nor_500
    end

    [
      {latitude: "abc"},
      {latitude: 91},
      {longitude: -181},
      {latitude: "NaN"}
    ].each do |bad_coordinate|
      it "stores no coordinates and no key for #{bad_coordinate.inspect}" do
        post_json_body({sway_registration: complete_params.merge(bad_coordinate)})

        expect(expect_one_stored_address_for(user)).to have_attributes(
          latitude: nil, longitude: nil, normalized_key: nil, street: "100 N Holliday St"
        )
      end
    end

    it "gives two users who both send an invalid latitude two different address rows" do
      other_user = create(:user, is_registration_complete: false, registration_status: "pending")

      post_json_body({sway_registration: complete_params.merge(latitude: "abc")})
      sign_in(other_user)
      post_json_body({sway_registration: complete_params.merge(latitude: "abc")})

      expect(user.reload.address.id).not_to eq(expect_one_stored_address_for(other_user).id)
    end

    it "stores coordinates and a key sent as JSON numbers" do
      post_json_body({sway_registration: complete_params})

      address = expect_one_stored_address_for(user)
      expect(address).to have_attributes(latitude: "39.29105", longitude: "-76.61069")
      expect(address.normalized_key).to eq(Address.normalized_key_for(latitude: 39.29105, longitude: -76.61069))
    end

    it "stores coordinates and a key sent as numeric strings" do
      post_json_body({sway_registration: complete_params.merge(latitude: "39.29105", longitude: "-76.61069")})

      address = expect_one_stored_address_for(user)
      expect(address).to have_attributes(latitude: "39.29105", longitude: "-76.61069")
      expect(address.normalized_key).to eq(Address.normalized_key_for(latitude: 39.29105, longitude: -76.61069))
    end

    it "redirects a browser that posts only a region and country instead of answering 400" do
      post "/sway_registration", params: {sway_registration: {region_code: "MD", country: "US"}}

      expect(response).to have_http_status(:redirect)
      expect(stored_address_for(user)).to have_attributes(street: "", city: "", postal_code: "", latitude: nil)
    end

    it "still answers 401 to an unauthenticated post" do
      session_hash.clear

      post_json_body({sway_registration: {}})

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
  describe "POST /sway_registration for a brand-new user through the real address-to-district path" do
    let!(:baltimore) { create(:sway_locale, :baltimore) }
    let!(:maryland) { create(:sway_locale, :maryland) }
    let!(:congress) { create(:sway_locale, :congress) }
    let!(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }

    def city_hall_address
      {
        street: "100 N Holliday St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US",
        latitude: 39.29105,
        longitude: -76.61069
      }
    end

    def columbus_address
      {
        street: "90 W Broad St",
        city: "Columbus",
        region_code: "OH",
        postal_code: "43215",
        country: "US",
        latitude: 39.96173,
        longitude: -83.00067
      }
    end

    def stub_census(status:, body:)
      stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/})
        .to_return(status:, body:)
    end

    def census_district_body(district)
      {features: [{attributes: {"CD#{Census::CURRENT_CONGRESS_NUMBER}" => district}}]}.to_json
    end

    def post_address(address)
      with_env("OPEN_STATES_API_KEY" => "test-open-states-key") do
        post "/sway_registration", params: {sway_registration: address}, headers: {"Accept" => "application/json"}
      end
    end

    def linked_seats
      UserLegislator.where(user:, active: true).map do |user_legislator|
        term = user_legislator.legislator.active_term
        [term.district.sway_locale.name, term.district.name, term.seat.title]
      end
    end

    def active_district_names
      UserDistrict.where(user:, active: true).map { |user_district| [user_district.district.sway_locale.name, user_district.district.name] }
    end

    before do
      SeedLegislator.run([baltimore, maryland, congress])
      sign_in(user)
      allow(Sentry).to receive(:capture_exception)
      stub_request(:get, %r{v3\.openstates\.org/people\.geo}).to_return(status: 200, body: {results: []}.to_json)
    end

    it "links a Baltimore City Hall address to its city, state and Congress representatives" do
      stub_census(status: 200, body: census_district_body("07"))
      expect(UserLegislator.where(user:)).to be_empty
      expect(UserAddress.where(user:)).to be_empty

      post_address(city_hall_address)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["registration_status"]).to eq("completed")
      expect(user.reload.registered?).to be(true)
      expect(user.pending_representative_locale_ids).to eq([])
      expect(UserAddress.where(user:).count).to eq(1)
      expect(Address.count).to eq(1)
      expect(user.address.normalized_key).to eq(Address.normalized_key_for(latitude: 39.29105, longitude: -76.61069))
      expect(linked_seats).to contain_exactly(
        [baltimore.name, "MD0", "Mayor"],
        [baltimore.name, "MD0", "Council President"],
        [baltimore.name, "MD11", "Council Member"],
        [maryland.name, "MD0", "Governor"],
        [congress.name, "MD0", "Sen."],
        [congress.name, "MD0", "Sen."],
        [congress.name, "MD7", "Rep."]
      )
      expect(active_district_names).to contain_exactly(
        [baltimore.name, "MD0"],
        [baltimore.name, "MD11"],
        [maryland.name, "MD0"],
        [congress.name, "MD0"],
        [congress.name, "MD7"]
      )
      expect(Sentry).not_to have_received(:capture_exception)
    end

    census_failures = [
      ["answers HTTP 502 with HTML", 502, "<html><body>Bad Gateway</body></html>"],
      ["answers HTTP 200 with an error object", 200, {error: {code: 500, message: "Unable to complete operation."}}.to_json]
    ] #: Array[[String, Integer, String]]
    census_failures.each do |census_failure, status, body|
      it "completes with the Senators and records Congress for later when Census #{census_failure}" do
        stub_census(status:, body:)

        post_address(city_hall_address)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["registration_status"]).to eq("completed")
        expect(response.parsed_body.dig("error", "code")).to be_nil
        expect(UserAddress.where(user:).count).to eq(1)
        expect(linked_seats).to contain_exactly(
          [baltimore.name, "MD0", "Mayor"],
          [baltimore.name, "MD0", "Council President"],
          [baltimore.name, "MD11", "Council Member"],
          [maryland.name, "MD0", "Governor"],
          [congress.name, "MD0", "Sen."],
          [congress.name, "MD0", "Sen."]
        )
        expect(user.reload.pending_representative_locale_ids).to eq([congress.id])
        expect(Sentry).to have_received(:capture_exception)
          .with(an_instance_of(SwayGeocode::ServiceUnavailableError), level: :warning)
      end
    end

    it "still resolves representatives when a concurrent request stored the address link first" do
      stub_census(status: 200, body: census_district_body("07"))
      UserAddress.create!(user:, address: create(:address, **city_hall_address.except(:country)))
      allow_any_instance_of(User).to receive(:user_address).and_return(nil) # rubocop:disable RSpec/AnyInstance

      post_address(city_hall_address)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["registration_status"]).to eq("completed")
      expect(UserAddress.where(user:).count).to eq(1)
      expect(user.reload.registered?).to be(true)
      expect(linked_seats).to include([baltimore.name, "MD0", "Mayor"], [congress.name, "MD7", "Rep."])
    end

    it "links an address in a place Sway does not support to its Congress representatives only" do
      stub_census(status: 200, body: census_district_body("03"))

      post_address(columbus_address)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["registration_status"]).to eq("completed")
      expect(user.reload.registered?).to be(true)
      expect(linked_seats).to contain_exactly(
        [congress.name, "OH0", "Sen."],
        [congress.name, "OH0", "Sen."],
        [congress.name, "OH3", "Rep."]
      )
    end
  end

  describe "POST /sway_registration with the flat JSON body the registration form sends" do
    let(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }
    let(:form_body) do
      {
        is_voter_registration_address_confirmed: false,
        street: "100 Holliday Street",
        city: "Baltimore",
        region: "Maryland",
        region_code: "MD",
        postal_code: "21202",
        country: "United States",
        latitude: 39.2904,
        longitude: -76.6122,
        place_types: ["house", "place"]
      }
    end

    let(:inertia_headers) do
      {"Accept" => "text/html, application/xhtml+xml", "X-Requested-With" => "XMLHttpRequest", "X-Inertia" => "true"}
    end

    before { sign_in(user) }

    def expect_stored_form_address
      expect(response).not_to have_http_status(:bad_request)
      expect(response).to redirect_to(feed_path)
      expect(Address.count).to eq(1)

      address = Address.sole
      expect(UserAddress.where(user:).pluck(:address_id)).to eq([address.id])
      expect(address.street).to eq("100 Holliday Street")
      expect(address.city).to eq("Baltimore")
      expect(address.region_code).to eq("MD")
      expect(address.postal_code).to eq("21202")
      expect(address.country).to eq("United States")
      expect(address.latitude.to_f).to be_within(0.00001).of(39.2904)
      expect(address.longitude.to_f).to be_within(0.00001).of(-76.6122)
      expect(address.place_types).to eq(["house", "place"])
    end

    it "stores the address and links it to the user when the coordinates are numbers" do
      post "/sway_registration", params: form_body, headers: inertia_headers, as: :json

      expect_stored_form_address
    end

    it "stores the address and links it to the user when the coordinates are numeric strings" do
      post "/sway_registration",
        params: form_body.merge(latitude: "39.2904", longitude: "-76.6122"),
        headers: inertia_headers,
        as: :json

      expect_stored_form_address
    end
  end

  describe "GET /sway_registration page props for a pending user" do
    it "has no registration_outcome prop on a plain render" do
      setup_pre_registration

      get sway_registration_index_path

      expect(inertia).to render_component Pages::REGISTRATION
      expect(inertia).to have_no_prop(:registration_outcome)
    end

    it "shares the pending status, an incomplete registration and no address for a user with no address" do
      _sway_locale, user = setup_pre_registration

      get sway_registration_index_path

      expect(inertia).to have_props { |props|
        props[:user].slice("id", "registration_status", "is_registration_complete", "address") ==
          {"id" => user.id, "registration_status" => "pending", "is_registration_complete" => false, "address" => nil}
      }
    end

    it "shares the address fields the address-switch warning reads for a user with an address" do
      _sway_locale, user = setup_pre_registration
      address = create(:address)
      UserAddress.create!(user:, address:)

      get sway_registration_index_path

      expect(inertia).to have_props { |props|
        props[:user].slice("registration_status", "is_registration_complete") ==
          {"registration_status" => "pending", "is_registration_complete" => false} &&
          props[:user]["address"] == {
            "id" => address.id,
            "street" => address.street,
            "street2" => address.street2,
            "city" => address.city,
            "region_code" => address.region_code,
            "country" => address.country,
            "postal_code" => address.postal_code,
            "full_address" => address.full_address
          }
      }
    end
  end
end
