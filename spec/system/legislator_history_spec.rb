# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislators-tab-switching-design#Why Legislators.tsx switches tabs without a server round trip]]
RSpec.describe "Legislator history tab", type: :system, js: true do
  # @lat: [[legislator-history-serialization#Why session label uses declared jurisdiction rules with year fallback]]
  let(:sway_locale) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }

  def open_history_tab
    find("[id$='-trigger-history']").click
    wait_until_loaded
  end

  it "shows deactivated links grouped by session with frozen scores and the Ended stamp" do
    legislator = create(:legislator, district: district)
    term = create(:legislator_term, legislator: legislator, district: district,
      term_start_year: 2023, term_end_year: 2025)

    user = create(:user)
    complete_registration_with_active_link(user, legislator: create(:legislator, district: district))
    user_legislator = create(:user_legislator, user: user, legislator: legislator, active: false)
    create(:user_legislator_term_score, user_legislator: user_legislator, legislator_term: term,
      count_agreed: 4, count_disagreed: 1, count_no_legislator_vote: 0, count_legislator_abstained: 0)

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    open_history_tab

    # The group header. For a locale that is neither Congress nor a whole
    # region, LegislatorHistoryResource#session_label reads
    # "{start}–{end} City Council".
    expect(page).to have_text("2023–2025 City Council", wait: 10)
    expect(page).to have_text(legislator.full_name)
    expect(page).to have_css("[data-testid='legislator-card-ended-stamp']", text: "Ended")
    expect(page).to have_text("2023–2025")

    # The score frozen at the end of that term — 4 agreed, 1 disagreed — with
    # nothing else added into it.
    agreed_value =
      find(:xpath, "//div[normalize-space(text())='Agreed']/following-sibling::div[1]").text
    expect(agreed_value).to eq("4")
  end

  it "renders the friendly empty state when the user has no deactivated links" do
    user = create(:user)
    complete_registration_with_active_link(user, legislator: create(:legislator, district: create(:district, sway_locale: sway_locale)))

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    open_history_tab

    expect(page).to have_css("[data-testid='legislators-history-empty']", wait: 10)
    expect(page).to have_text("No history yet")
    expect(page).to have_text("History builds when terms end or your representatives change.")
  end

  # @lat: [[legislators-history-per-locale-state#Switching locale while History is open or closed]]
  it "stays on the History tab across a locale switch and shows that locale's history" do
    congress = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
    congress_district = create(:district, sway_locale: congress, name: "MD0")
    former_senator = create(:legislator, district: congress_district)
    term = create(:legislator_term, legislator: former_senator, district: congress_district,
      term_start_year: 2017, term_end_year: 2023, title: "Sen.")

    user = create(:user)
    active_district = create(:district, sway_locale: sway_locale)
    active_legislator = create(:legislator, district: active_district)
    complete_registration_with_active_link(user, legislator: active_legislator)
    # The locale dropdown lists the locales worked out from the user's address,
    # so a user with no address gets no options to switch to.
    address = create(:address)
    create(:user_address, user:, address:)
    user_legislator = create(:user_legislator, user: user, legislator: former_senator, active: false)
    create(:user_legislator_term_score, user_legislator: user_legislator, legislator_term: term,
      count_agreed: 2, count_disagreed: 3, count_no_legislator_vote: 0, count_legislator_abstained: 0)

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    open_history_tab
    # The home locale has no past representatives, so seeing the empty state
    # proves the History tab is showing only this locale.
    expect(page).to have_css("[data-testid='legislators-history-empty']", wait: 10)

    select "U.S. Congress", from: "v2-locale"
    wait_until_loaded

    # Still on History, not snapped back to Current term, and now showing the
    # Congress locale: the former senator appears with the Ended stamp.
    expect(page).to have_css("[id$='-trigger-history'][data-state='active']", wait: 10)
    expect(page).to have_text(former_senator.full_name, wait: 10)
    expect(page).to have_css("[data-testid='legislator-card-ended-stamp']", text: "Ended")
  end

  # @lat: [[legislators-controller-design#Forced history failure is test-only]]
  it "shows the error state with a retry affordance on a history fetch failure, and retry re-issues the request (WR-04)" do
    user = create(:user)
    complete_registration_with_active_link(user)

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}&_test_force_history_error=1"
    wait_until_loaded

    page.execute_script(<<~JS)
      window.__swayHistoryRequestCount = 0;
      const origOpen = window.XMLHttpRequest.prototype.open;
      window.XMLHttpRequest.prototype.open = function (method, url, ...rest) {
        if (String(url).includes("_test_force_history_error")) {
          window.__swayHistoryRequestCount += 1;
        }
        return origOpen.call(this, method, url, ...rest);
      };
    JS

    open_history_tab

    expect(page).to have_css("[data-testid='legislators-history-error']", wait: 10)
    expect(page).to have_text("Couldn't load your history. Try again.")
    wait_until { page.evaluate_script("window.__swayHistoryRequestCount") == 1 }

    click_testid("legislators-history-retry-button")
    wait_until_loaded

    expect(page).to have_css("[data-testid='legislators-history-error']", wait: 10)
    wait_until { page.evaluate_script("window.__swayHistoryRequestCount") == 2 }
  end
end
