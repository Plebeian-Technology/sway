# frozen_string_literal: true

require "rails_helper"

# @lat: [[user-vote-submission#The stale browser panel returns to the server's final vote]]
RSpec.describe "VotePanel server-finality failure", type: :system, js: true do
  include_context "TwilioDouble"
  include ActiveJob::TestHelper

  let(:sway_locale) do
    SwayLocale.find_by(
      city: "baltimore",
      state: "MD",
      country: "United States"
    ) ||
      create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

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
    # Create the baltimore locale from the test's own thread FIRST. Otherwise
    # the web-server thread may try to insert the same city, state, and country
    # during register_passkey_user and the two collide.
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
    create(:user_legislator, user: @signed_in_user, legislator: legislator)
    @signed_in_user.complete!

    # Fake out the score broadcast so the WebSocket push cannot race the test.
    allow(ScoreChannel).to receive(:broadcast_to)
    allow(ActionCable.server).to receive(:broadcast)

    ActiveJob::Base.queue_adapter = :test
  end

  after do
    Array(@active_authenticators).reverse_each do |id|
      disable_virtual_authenticator(id)
    end
  end

  it "rejects a stale-client FOR via server finality and does not leave a FOR recorded" do
    bill = create(:bill, sway_locale: sway_locale, legislator: legislator)

    visit bill_path(bill)

    # The panel is live because no vote has been recorded yet.
    expect(page).to have_button("For", wait: 10)
    expect(page).to have_no_css("[data-testid='vote-recorded']")

    # Another device records an AGAINST vote after this page loaded, so what the
    # page is showing is now out of date.
    create(:user_vote, :against, user: @signed_in_user, bill: bill)

    click_button("For", match: :first)
    within("[role='dialog']") { click_button("Cast vote") }

    # @lat: [[user-vote-submission#The stale browser panel returns to the server's final vote]]
    expect(page).to have_text("You recorded an Against vote on this bill.", wait: 15)
    expect(page).to have_no_text("You recorded a For vote on this bill.")

    votes = UserVote.where(user_id: @signed_in_user.id, bill_id: bill.id)
    expect(votes.count).to eq(1)
    expect(votes.first&.support).to eq("AGAINST")

    expect(page).to have_current_path(bill_path(bill))
  end
end
