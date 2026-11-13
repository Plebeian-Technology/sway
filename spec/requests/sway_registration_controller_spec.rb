# frozen_string_literal: true

require "rails_helper"

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
      create_seat_term(
        district: create(:district, sway_locale: baltimore, name: "MD0"),
        seat_identifier: "baltimore-mayor",
        title: "Mayor",
        years: [2024, 2028]
      )
    end
    let!(:house_member) do
      create_seat_term(
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

    def create_seat_term(district:, seat_identifier:, title:, years:)
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
      expect(Sentry).to have_received(:capture_exception).with(
        an_instance_of(JSON::ParserError),
        extra: hash_including(user_id: user.id, sway_locale: congress.name)
      )
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
      create_seat_term(
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

    it "reports every locale and ends without a 500 when every locale is skipped" do
      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_raise( # rubocop:disable RSpec/AnyInstance
        SwayGeocode::ServiceUnavailableError,
        "geocoding is unavailable"
      )

      post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

      expect(response).not_to have_http_status(:internal_server_error)
      expect(UserLegislator.where(user:)).to be_empty
      [baltimore, maryland, congress].each do |sway_locale|
        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(SwayGeocode::ServiceUnavailableError),
          extra: hash_including(sway_locale: sway_locale.name)
        )
      end
    end
  end

  describe "POST /sway_registration when no representatives match the address" do
    let!(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "MD", country: "US") }
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

    before do
      sign_in(user)
      allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_return([]) # rubocop:disable RSpec/AnyInstance
    end

    it "returns the safe 422 error envelope for mobile callers" do
      post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.keys).to eq(["error"])
      expect(response.parsed_body.fetch("error").keys).to match_array(%w[code message])
      expect(response.parsed_body.dig("error", "code")).to eq("no_representatives")
      expect(response.parsed_body.dig("error", "message")).to eq(
        SwayRegistrationController::REGISTRATION_NO_REPRESENTATIVES_MESSAGE
      )
      expect(user.reload.registration_status).to eq("pending")
      expect(user.is_registration_complete).to be(false)
    end

    it "carries the reason into the Registration page props after a browser redirect" do
      post "/sway_registration", params: address_params

      expect(response).to redirect_to(sway_registration_index_path)
      get sway_registration_index_path,
        headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
          "User-Agent" => "RSpec Browser"
        }

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::REGISTRATION)
      expect(inertia).to have_props { |props|
        outcome = props[:registration_outcome] || props["registration_outcome"]
        outcome.present? && outcome[:reason].to_s == "no_representatives" &&
          outcome[:message] == SwayRegistrationController::REGISTRATION_NO_REPRESENTATIVES_MESSAGE
      }
    end

    it "does not report success from a stale completed status with no active pairing" do
      user.update_columns(registration_status: "completed", is_registration_complete: true)

      post "/sway_registration", params: address_params, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("no_representatives")
      expect(user.reload.registration_status).to eq("completed")
      expect(user.is_registration_complete).to be(true)
      expect(user.registered?).to be(false)
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
end
