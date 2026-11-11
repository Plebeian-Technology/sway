# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislators-controller-design#Detail page has its own response]]
RSpec.describe "Legislator Detail Page", type: :system, js: true do
  include_context "TwilioDouble"

  let(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) do
    create(:legislator, district: district).tap do |l|
      l.update!(email: "rep@example.com")
      # @lat: [[legislators-controller-design#Active term is loaded before detail serialization]]
      create(:legislator_term, legislator: l, district: district)
    end
  end

  around do |example|
    initial_values = {} #: Hash[String, String?]
    env_overrides = {
      "TWILIO_ACCOUNT_SID" => "test-sid",
      "TWILIO_AUTH_TOKEN" => "test-token"
    }
    previous_values =
      env_overrides.each_with_object(initial_values) do |(key, _value), memo|
        memo[key] = ENV.fetch(key, nil)
      end

    begin
      env_overrides.each { |key, value| ENV[key] = value }

      example.run
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end

  before do
    sway_locale

    visit root_path
    @active_authenticators = [enable_virtual_authenticator]

    phone = "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
    @signed_in_user = register_passkey_user(phone: phone)
    create(
      :address,
      city: "baltimore",
      region_code: "MD",
      country: "United States"
    ).tap { |address| set_user_address(@signed_in_user, address) }

    user_legislator =
      create(:user_legislator, user: @signed_in_user, legislator: legislator, active: true)
    @signed_in_user.complete!
    # The charts panel reads the score for a single term
    # (UserLegislatorTermScoreResource). The older UserLegislatorScore, which
    # summed a legislator's whole career, is retired.
    UserLegislatorTermScore.find_or_create_by!(
      user_legislator: user_legislator, legislator_term: legislator.active_term
    )
  end

  after do
    Array(@active_authenticators).reverse_each do |id|
      disable_virtual_authenticator(id)
    end
  end

  it "renders the voter-agreement charts and contact rows for a scored legislator" do
    visit legislator_path(legislator)

    # The charts appear only when the signed-in user has a score for this one.
    expect(page).to have_css("[data-testid='legislator-detail-charts']", wait: 10)

    # The contact section and its email row (a mailto: link) come from
    # legislator.email.
    expect(page).to have_css("[data-testid='legislator-detail-contact']", wait: 10)
    expect(page).to have_css("[data-testid='legislator-detail-email']", wait: 10)
    expect(page).to have_text("rep@example.com")
  end
end
