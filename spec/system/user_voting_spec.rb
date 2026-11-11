# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User Voting Flow", type: :system, js: true do
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
    # during register_passkey_user and collide. Once the row exists, attempts on
    # the server side find it and do nothing, so the uniqueness rule never trips.
    sway_locale

    visit root_path
    @active_authenticators = [enable_virtual_authenticator]

    phone = "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
    @signed_in_user =
      register_passkey_user(phone: phone)
    create(
      :address,
      city: "baltimore",
      region_code: "MD",
      country: "United States"
    ).tap { |address| set_user_address(@signed_in_user, address) }
    create(:user_legislator, user: @signed_in_user, legislator: legislator)
    @signed_in_user.complete!

    # A Bill of the Month for this user's locale. The :bill_of_the_month trait
    # sets scheduled_release_date_utc to today.
    @bill_of_the_month =
      create(
        :bill,
        :bill_of_the_month,
        sway_locale: sway_locale,
        legislator: legislator
      )

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

  it "votes FOR on the bill of the month and sees score update + legislator comparison" do
    # register_passkey_user finishes the passkey registration, which also signs
    # the user in. The test-only sign-in route makes sure the browser really
    # holds the session cookie.
    visit bill_of_the_month_index_path

    # The Bill of the Month page loads with a "For" button. The button reads
    # "For" with "Support this legislation" underneath, both inside the same
    # <button>, so match part of the text rather than the whole label.
    expect(page).to have_button("For", wait: 10)

    # Click For, then confirm in the app's own React dialog. It is not the
    # browser's window.confirm, so Capybara's accept_confirm cannot drive it;
    # click the dialog's "Cast vote" button instead.
    click_button("For", match: :first)
    within("[role='dialog']") { click_button("Cast vote") }

    # The "vote recorded" wrapper appears around the vote buttons. It shows as
    # soon as the chosen side is written into the form data, which happens
    # right away inside createVote, before the request goes out.
    expect(page).to have_css("[data-testid='vote-recorded']", wait: 10)

    # @lat: [[user-vote-submission#User vote submission#Themed web vote controls]]
    expect(page).to have_text("Vote saved!", wait: 15)
    user_vote = UserVote.find_by(user_id: @signed_in_user.id, bill_id: @bill_of_the_month.id)

    # Run the queued score-update jobs right here so the page can update.
    perform_enqueued_jobs

    # @lat: [[user-vote-submission#User vote submission#Themed web vote controls]]
    expect(user_vote).to be_present, "expected UserVote row to be persisted for user and bill"
    expect(user_vote.support).to eq("FOR")

    # The score panel renders with aria-live "polite", so a screen reader
    # announces its updates without cutting in.
    expect(page).to have_css("[data-testid='score-panel']", wait: 15)

    expect(page).to have_css("[data-testid='legislator-comparison']", wait: 10)
  end

  # @lat: [[user-vote-submission#Browser examples prove the web vote reached the server]]
  it "votes For on a regular bill show page and persists the UserVote" do
    regular_bill =
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator
      )

    visit bill_path(regular_bill)

    expect(page).to have_button("For", wait: 10)

    click_button("For", match: :first)
    within("[role='dialog']") { click_button("Cast vote") }

    expect(page).to have_css("[data-testid='vote-recorded']", wait: 10)

    # Wait for the "Vote saved!" toast, which only appears on Inertia's success
    # event after UserVotesController#create has saved — not the vote-recorded
    # marker, which flips on before the request is even sent. Never sleep.
    expect(page).to have_text("Vote saved!", wait: 15)
    user_vote = UserVote.find_by(user_id: @signed_in_user.id, bill_id: regular_bill.id)

    perform_enqueued_jobs

    expect(user_vote).to be_present, "expected UserVote row to be persisted for the regular bill"
    expect(user_vote.support).to eq("FOR")
  end
end
