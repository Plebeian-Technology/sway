# frozen_string_literal: true

require "rails_helper"

# @lat: [[web-profile-page#Web profile page#Changing the address from the web]]
RSpec.describe "Changing a registered user's address on the web", type: :request do
  include_context "SessionDouble"

  let!(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "MD", country: "US") }
  let!(:legislator) { create(:legislator, sway_locale: sway_locale) }
  let!(:user) { complete_registration_with_active_link(create(:user), legislator: legislator) }
  let!(:current_address) do
    create(:address, street: "100 N Holliday St", city: "Baltimore", region_code: "MD", postal_code: "21202",
      country: "US", latitude: 39.29105, longitude: -76.61069)
  end
  let(:inertia_headers) { {"X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s} }
  let(:new_address_params) do
    {
      street: "100 Light St",
      city: "Baltimore",
      region_code: "MD",
      postal_code: "21202",
      country: "US",
      latitude: 39.2851,
      longitude: -76.6141
    }
  end

  before do
    UserAddress.create!(user: user, address: current_address)
    sign_in(user)
    allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
    allow(Sentry).to receive(:capture_exception)
    allow(Sentry).to receive(:capture_message)
  end

  def submit_new_address(**overrides)
    post "/sway_registration",
      params: {sway_registration: new_address_params.merge(change_address: true).merge(overrides)},
      headers: inertia_headers
  end

  def expect_back_on_change_address_page(error_code:, message:)
    expect(response).to redirect_to(edit_users_address_path)
    follow_redirect!
    expect(inertia).to render_component(Pages::REGISTRATION)
    expect(inertia).to have_props(change_address: true, errors: {code: error_code, message: message})
    expect(user.reload.address).to eq(current_address)
    expect(UserLegislator.find_by!(user: user, legislator: legislator).active).to be(true)
    expect(UserAddressChange.count).to eq(0)
  end

  describe "GET /users/address/edit" do
    it "renders the registration form in change-address mode with the current address" do
      get edit_users_address_path

      expect(inertia).to render_component(Pages::REGISTRATION)
      expect(inertia).to have_props(change_address: true, current_address: current_address.full_address)
    end

    it "sends a user who has not registered yet to first-time registration" do
      unregistered = create(:user)
      sign_in(unregistered)

      get edit_users_address_path

      expect(response).to redirect_to(sway_registration_index_path)
    end
  end

  describe "an address switch that does not happen" do
    it "asks for confirmation on the change-address page" do
      submit_new_address

      expect_back_on_change_address_page(
        error_code: "confirmation_required",
        message: SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_CONFIRMATION_MESSAGE
      )
    end

    it "shows the cooldown on the change-address page" do
      create(:user_address_change, user: user, previous_address: create(:address, street: "1 E Pratt St"),
        new_address: current_address, created_at: 2.days.ago)

      submit_new_address(confirm_deactivate_legislators: true)

      expect(response).to redirect_to(edit_users_address_path)
      follow_redirect!
      expect(inertia).to have_props(
        change_address: true,
        errors: {code: "address_switch_cooldown", message: SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_COOLDOWN_MESSAGE}
      )
      expect(user.reload.address).to eq(current_address)
      expect(UserAddressChange.count).to eq(1)
    end

    it "shows that geocoding is unavailable on the change-address page" do
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators) # rubocop:disable RSpec/AnyInstance
        .and_raise(SwayGeocode::ServiceUnavailableError, "Census TIGERweb geocoding is unavailable")

      submit_new_address(confirm_deactivate_legislators: true)

      expect_back_on_change_address_page(
        error_code: "geocoding_unavailable",
        message: SwayRegistrationController::REGISTRATION_UNAVAILABLE_MESSAGE
      )
    end

    it "shows that the switch is unavailable on the change-address page" do
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators) # rubocop:disable RSpec/AnyInstance
        .and_raise(RuntimeError, "unexpected resolution failure")

      submit_new_address(confirm_deactivate_legislators: true)

      expect_back_on_change_address_page(
        error_code: "registration_unavailable",
        message: SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_UNAVAILABLE_MESSAGE
      )
    end

    it "shows the retry message on the change-address page when an unexpected error is raised before the switch" do
      allow(UserAddressSwitchService).to receive(:cooldown_active_for?).and_raise(RuntimeError, "boom")

      submit_new_address(confirm_deactivate_legislators: true)

      expect(response).to redirect_to(edit_users_address_path)
      expect(flash[:alert]).to eq(OnboardingSafetyNet::ONBOARDING_UNAVAILABLE_MESSAGE)
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), any_args).once
      expect(user.reload.address).to eq(current_address)
      expect(UserLegislator.find_by!(user: user, legislator: legislator).active).to be(true)
      expect(UserAddressChange.count).to eq(0)
    end

    it "shows that no representatives were found on the change-address page" do
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_return([]) # rubocop:disable RSpec/AnyInstance

      submit_new_address(confirm_deactivate_legislators: true)

      expect_back_on_change_address_page(
        error_code: "no_representatives",
        message: SwayRegistrationController::REGISTRATION_NO_REPRESENTATIVES_MESSAGE
      )
      expect(inertia).to have_props(
        registration_outcome: {"reason" => "no_representatives", "message" => SwayRegistrationController::REGISTRATION_NO_REPRESENTATIVES_MESSAGE}
      )
    end
  end

  it "shows the address-not-located outcome on the change-address page after switching to an unlocated address" do
    allow(Geocoder).to receive(:search).and_return([])
    allow_any_instance_of(UserAddressSwitchService).to receive(:call).and_return(true) # rubocop:disable RSpec/AnyInstance

    submit_new_address(street: "123 Main St", city: "", region_code: "", postal_code: "", country: "",
      latitude: nil, longitude: nil, confirm_deactivate_legislators: true)

    expect(response).to redirect_to(edit_users_address_path)
    follow_redirect!
    expect(inertia).to render_component(Pages::REGISTRATION)
    expect(inertia).to have_props(
      change_address: true,
      registration_outcome: {"reason" => "address_not_located", "message" => SwayRegistrationController::ADDRESS_NOT_LOCATED_MESSAGE}
    )
  end

  it "keeps a registered user with an unlocated address on the change-address page when the new address is still unlocated" do
    unlocated_user = create(:user)
    unlocated = create(:address, street: "123 Main St", city: "", region_code: "", postal_code: "", country: "",
      latitude: nil, longitude: nil)
    UserAddress.create!(user: unlocated_user, address: unlocated)
    unlocated_user.add_pending_representative_locale(sway_locale)
    unlocated_user.complete_registration!
    sign_in(unlocated_user)
    allow(Geocoder).to receive(:search).and_return([])
    allow_any_instance_of(SwayRegistrationService).to receive(:call) # rubocop:disable RSpec/AnyInstance

    submit_new_address(street: "456 Oak Ave", city: "", region_code: "", postal_code: "", country: "",
      latitude: nil, longitude: nil)

    expect(response).to redirect_to(edit_users_address_path)
    follow_redirect!
    expect(inertia).to render_component(Pages::REGISTRATION)
    expect(inertia).to have_props(
      change_address: true,
      registration_outcome: {"reason" => "address_not_located", "message" => SwayRegistrationController::ADDRESS_NOT_LOCATED_MESSAGE}
    )
  end

  it "keeps first-time registration outcomes on the registration page" do
    first_timer = create(:user)
    sign_in(first_timer)
    allow(Geocoder).to receive(:search).and_return([])

    post "/sway_registration",
      params: {sway_registration: {street: "123 Main St", city: "", region_code: "", postal_code: "", country: ""}},
      headers: inertia_headers

    expect(response).to redirect_to(sway_registration_index_path)
  end

  it "keeps a first-time user's second unlocated save on the registration page" do
    first_timer = create(:user)
    sign_in(first_timer)
    allow(Geocoder).to receive(:search).and_return([])
    unlocated_params = {sway_registration: {street: "123 Main St", city: "", region_code: "", postal_code: "", country: ""}}

    post "/sway_registration", params: unlocated_params, headers: inertia_headers
    expect(response).to redirect_to(sway_registration_index_path)
    expect(first_timer.reload.registered?).to be(true)

    post "/sway_registration",
      params: {sway_registration: unlocated_params[:sway_registration].merge(street: "456 Oak Ave")},
      headers: inertia_headers

    expect(response).to redirect_to(sway_registration_index_path)
  end

  it "keeps a registered user's save without the change-address marker on the registration page" do
    allow(Geocoder).to receive(:search).and_return([])
    allow_any_instance_of(UserAddressSwitchService).to receive(:call).and_return(true) # rubocop:disable RSpec/AnyInstance

    submit_new_address(street: "123 Main St", city: "", region_code: "", postal_code: "", country: "",
      latitude: nil, longitude: nil, confirm_deactivate_legislators: true, change_address: nil)

    expect(response).to redirect_to(sway_registration_index_path)
  end
end
