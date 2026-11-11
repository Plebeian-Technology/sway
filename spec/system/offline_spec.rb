# frozen_string_literal: true

require "rails_helper"

# @lat: [[client-caches-and-identity#Offline interaction regression]]
RSpec.describe "Offline Support", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:user) do
    create(:user).tap do |user|
      complete_registration_with_active_link(user)
    end
  end
  let(:bill) do
    create(
      :bill,
      :bill_of_the_month,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Already loaded bill"
    )
  end

  before do
    create(:legislator_term, legislator: legislator, district: district)
    create(:user_address, user: user, address: create(:address, city: "baltimore", region_code: "MD", country: "United States"))
    create(:user_legislator, user: user, legislator: legislator)
  end

  # @lat: [[client-caches-and-identity#Offline interaction regression]]
  after do
    begin
      go_online!
    ensure
      page.driver.quit
    end
  rescue
    nil
  end

  context "when the user loses connectivity on a loaded bill page" do
    it "keeps the loaded bill visible and explains that new pages need a connection" do
      bill

      sign_in_as(user)

      visit bill_path(bill)
      expect(page).to have_text(bill.title, wait: 10)

      go_offline!

      expect(page).to have_text(bill.title, wait: 10)
      expect(page).to have_css("[data-testid='offline-banner']", text: "You're offline. Reconnect to load pages and vote.", wait: 5)

      go_online!
    end
  end

  context "when user attempts to vote offline" do
    it "keeps the vote unsaved and reasserts the dismissed offline banner" do
      bill

      sign_in_as(user)
      visit bill_path(bill)
      expect(page).to have_text(bill.title, wait: 10)

      expect(page).to have_css("button:not([disabled])", text: "Support this legislation", visible: :visible, wait: 5)

      go_offline!

      within("[data-testid='offline-banner']") { click_button("Dismiss") }
      expect(page).to have_no_css(
        "[data-testid='offline-banner']",
        text: "You're offline",
        visible: :visible,
        wait: 2
      )

      expect(page).to have_css("button:not([disabled])", text: "Support this legislation", visible: :visible, wait: 5)
      expect do
        click_button(text: "Support this legislation", visible: :visible, match: :first)
        within("[role='dialog']") { click_button("Cast vote") }
        expect(page).to have_css("[role='alert']", text: /online to vote/i, wait: 5)
      end.not_to change { UserVote.where(user: user, bill: bill).count }

      expect(page).to have_css(
        "[data-testid='offline-banner']",
        text: "Still offline. Reconnect to load pages and vote.",
        wait: 5
      )

      go_online!
    end
  end

  context "when the user reconnects" do
    it "auto-hides the offline banner on the online event" do
      bill

      sign_in_as(user)
      visit bill_path(bill)
      expect(page).to have_text(bill.title, wait: 10)

      go_offline!
      expect(page).to have_css("[data-testid='offline-banner']", text: "You're offline. Reconnect to load pages and vote.", wait: 5)

      go_online!
      expect(page).to have_no_css(
        "[data-testid='offline-banner']",
        text: "You're offline",
        wait: 5
      )
    end
  end
end
