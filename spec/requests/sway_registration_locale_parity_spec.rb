# frozen_string_literal: true

# @lat: [[sway-registration-controller-notes#What AddressScreen.parity.test.tsx deliberately does not cover]]

require "rails_helper"

RSpec.describe "POST /sway_registration locale parity (SC-2b)", type: :request do
  include_context "SessionDouble"

  # Build the Baltimore locale the controller path should resolve to.
  let!(:baltimore_locale) do
    create(:sway_locale, city: "Baltimore", state: "MD", country: "US")
  end

  # Supporting records needed to create a UserLegislator during the stub.
  let!(:district) { create(:district, sway_locale: baltimore_locale) }
  let!(:legislator) { create(:legislator, district: district) }

  # Pre-registration user (no address, no legislators yet).
  let!(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }

  before do
    sign_in(user)

    # Address#sway_locales calls this three times: city, state and congress.
    # Return baltimore_locale every time, so the loop that follows still runs
    # without real geocoding or extra database rows.
    allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(baltimore_locale)

    # @lat: [[sway-registration-controller-notes#What AddressScreen.parity.test.tsx deliberately does not cover]]
    UserLegislator.find_or_create_by!(user: user, legislator: legislator)

    allow_any_instance_of(SwayRegistrationService).to receive(:call) # rubocop:disable RSpec/AnyInstance
  end

  it "resolves the user's sway_locales to include the Baltimore locale for a Baltimore address" do
    post "/sway_registration", params: {
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
    }, headers: {"Accept" => "application/json"}

    expect(response).to have_http_status(:ok)

    # user.sway_locales hands off to user.address.sway_locales, which calls
    # find_or_create_by_normalized! — faked above to return baltimore_locale.
    # This is the same locale lookup the web and mobile clients both use.
    locale_ids = user.reload.sway_locales.map(&:id)
    expect(locale_ids).to include(baltimore_locale.id)
  end
end
