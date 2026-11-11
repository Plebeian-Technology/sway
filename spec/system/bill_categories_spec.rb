# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-categories-spec#The bill categories browser spec]]
RSpec.describe "Bill categories", type: :system, js: true do
  let(:admin_phone) { "4105550009" }

  let(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  around do |example|
    original_admin_phones = User::ADMIN_PHONES.dup

    begin
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])

      example.run
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, original_admin_phones)
    end
  end

  # ── The /bills category filter ──────────────────────────────────────────────
  # /bills#index skips the sign-in check, so no login is needed here. The locale
  # comes in as ?sway_locale_id so the bills query knows where to look.
  describe "web /bills category filter (UAT Test 2 + 3)" do
    let!(:housing) { create(:category, name: "Housing", active: true) }
    # @lat: [[bill-categories-spec#What the spec pins]]
    let!(:budget) { create(:category, name: "Budget & Taxes", active: true) }
    let!(:public_safety) { create(:category, name: "Public Safety", active: true) }

    # Each bill needs its own scheduled_release_date_utc: the database forbids
    # two bills in the same locale from sharing that date, and the factory would
    # otherwise give every bill the same default of one day ago.
    let!(:housing_bill) do
      create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Housing Act One",
        scheduled_release_date_utc: 3.days.ago).tap do |b|
        create(:bill_category, bill: b, category: housing)
      end
    end
    let!(:safety_bill) do
      create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Safety Act Two",
        scheduled_release_date_utc: 5.days.ago).tap do |b|
        create(:bill_category, bill: b, category: public_safety)
      end
    end

    it "renders the active taxonomy verbatim and filters bills via the URL selection" do
      visit "/bills?sway_locale_id=#{sway_locale.id}"
      wait_until_loaded
      open_category_filter

      # The options ARE the active category names, Title Case, printed as stored.
      expect(page).to have_field("Housing", type: :checkbox)
      expect(page).to have_field("Public Safety", type: :checkbox)
      expect(page).to have_field("Budget & Taxes", type: :checkbox) # not "Budget &amp; Taxes", not re-capitalized

      # With nothing picked, both bills show; the separately loaded list is in.
      expect(page).to have_text("Housing Act One")
      expect(page).to have_text("Safety Act Two")

      # One option picked shows only its bills, and the pick lands in the URL.
      toggle_category "Housing"
      wait_until_loaded
      expect(page).to have_text("Housing Act One")
      expect(page).to have_no_text("Safety Act Two")
      expect(page).to have_current_path(/categories=Housing/)

      # A second option widens the list: a bill matching either one stays.
      toggle_category "Public Safety"
      wait_until_loaded
      expect(page).to have_text("Housing Act One")
      expect(page).to have_text("Safety Act Two")

      # Unpicking every option restores the full list and clears the URL bit.
      toggle_category "Housing"
      wait_until_loaded
      toggle_category "Public Safety"
      wait_until_loaded
      expect(page).to have_text("Housing Act One")
      expect(page).to have_text("Safety Act Two")
      expect(page).to have_no_current_path(/categories=/)
    end

    it "encodes the selection in the URL so it survives navigation away and back" do
      visit "/bills?sway_locale_id=#{sway_locale.id}"
      wait_until_loaded

      # Pick an option and the pick moves into the URL. Check the visible
      # filtering first, because that check waits for the request and the
      # re-render; only afterwards is the URL guaranteed to have been rewritten.
      toggle_category "Housing"
      wait_until_loaded
      expect(page).to have_no_text("Safety Act Two")
      expect(page).to have_current_path(/categories=Housing/)

      # @lat: [[bills-category-filter#Why the selection stays in the URL]]
      filtered_url = current_url
      visit "/bills/#{housing_bill.id}"
      wait_until_loaded
      visit filtered_url
      wait_until_loaded

      # @lat: [[bill-categories-spec#The round trip re-reads the URL and not the list]]
      expect(page).to have_current_path(/categories=Housing/)
      expect(page).to have_text("Housing Act One")
      expect(page).to have_no_text("Safety Act Two")
    end

    # @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#The bill count is drawn inside the deferred boundary]]
    it "displays structured loading cards under a throttled response and preserves keyboard focus" do
      visit "/legislators?sway_locale_id=#{sway_locale.id}"
      wait_until_loaded

      go_slow_link!
      begin
        visit "/bills?sway_locale_id=#{sway_locale.id}"

        # 1. Under delayed Bills response, reader sees meaningful loading state
        expect(page).to have_css("[aria-busy='true']", wait: 5)
        expect(page).to have_css(".placeholder-block", wait: 5)
        expect(page).to have_text("Loading bills…")
        expect(page).to have_no_text("No bills found")

        # 2. Keyboard focus is preserved on interactive controls outside Deferred
        search_input = find("[data-testid='input-search-bills']")
        search_input.click
        expect(page.driver.browser.switch_to.active_element).to eq(search_input.native)

        go_online!

        # 3. Once resolved, actual rows appear and skeletons unmount
        expect(page).to have_text("Housing Act One", wait: 20)
        expect(page).to have_text("Safety Act Two")
        expect(page).to have_no_css("[aria-busy='true']")
        expect(page).to have_no_css(".placeholder-block")
        expect(page.driver.browser.switch_to.active_element).to eq(search_input.native)
      ensure
        go_online!
      end
    end

    it "preserves category filter on browser back-navigation after viewing a bill" do
      visit "/bills?sway_locale_id=#{sway_locale.id}"
      wait_until_loaded

      toggle_category "Housing"
      wait_until_loaded
      expect(page).to have_text("Housing Act One")
      expect(page).to have_no_text("Safety Act Two")
      expect(page).to have_current_path(/categories=Housing/)

      visit "/bills/#{housing_bill.id}"
      wait_until_loaded
      expect(page).to have_text("Housing Act One")

      page.go_back

      expect(page).to have_current_path(/categories=Housing/)
      expect(page).to have_text("Housing Act One")
      expect(page).to have_no_text("Safety Act Two")
    end
  end

  # ── Managing categories at /admin/categories ────────────────────────────────
  describe "admin /admin/categories lifecycle (UAT Test 4 + 5)" do
    before do
      @sway_admin_user = create(:user, phone: admin_phone)
      address = create(:address, city: "baltimore", region_code: "MD", country: "United States")
      create(:user_address, user: @sway_admin_user, address: address)
      create(:user_legislator, user: @sway_admin_user, legislator: legislator)

      sign_in_as(@sway_admin_user)
      clear_browser_storage
    end

    it "adds a category, renames it, and hints reactivate on a deactivated-name collision (Test 4)" do
      # A category that already exists but is switched OFF, to clash with later.
      create(:category, name: "Environment", active: false)

      visit "/admin/categories"
      wait_until_loaded

      # Add it: the table shows it with a live bill count of 0.
      fill_in "new-category-name", with: "Immigration"
      click_button "Add category"
      wait_until_loaded
      expect(page).to have_text("Category added.")
      # @lat: [[bill-categories-spec#Rows are re-queried rather than held]]
      expect(page).to have_css("tr", text: /Immigration.*0/) # bill_count column

      # Rename it. Only the name changes; the slug stays as it was.
      within("tr", text: "Immigration") { click_button "Rename" }
      find("input[aria-label='Rename Immigration']").set("Immigration Policy")
      click_button "Save name"
      wait_until_loaded
      expect(page).to have_text("Category renamed.")
      expect(page).to have_text("Immigration Policy")

      # Reusing a switched-off category's name gives the reactivate hint, not a
      # generic "name taken" error.
      fill_in "new-category-name", with: "Environment"
      click_button "Add category"
      wait_until_loaded
      expect(page).to have_text("Reactivate it instead.")
      # And no second row was created: still exactly one "Environment".
      expect(page).to have_css("tr", text: "Environment", count: 1)
    end

    it "deactivating an assigned category drops its filter option but preserves the assignment (Test 5)" do
      housing = create(:category, name: "Housing", active: true)
      bill = create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Housing Act One")
      create(:bill_category, bill: bill, category: housing)

      visit "/admin/categories"
      wait_until_loaded

      # @lat: [[bill-categories-spec#Rows are re-queried rather than held]]
      expect(page).to have_css("tr", text: /Housing.*1/)

      # Switch it off, confirm in the dialog, and read the notice saying the
      # existing assignments are kept.
      within("tr", text: "Housing") { click_button "Deactivate" }
      within("[role='dialog']") { click_button "Deactivate" }
      wait_until_loaded
      expect(page).to have_text("Existing bill assignments are preserved")
      expect(page).to have_css("tr", text: /Housing.*Inactive/)

      # @lat: [[bill-categories-spec#Presence is established before absence]]
      visit "/bills?sway_locale_id=#{sway_locale.id}"
      expect(page).to have_text("Housing Act One", wait: 10)
      open_category_filter
      expect(page).to have_field("Filter categories…", wait: 10)
      expect(page).to have_no_field("Housing", type: :checkbox)

      # But switching the category off KEEPS the bill's assignment in the
      # database.
      expect(BillCategory.exists?(bill_id: bill.id, category_id: housing.id)).to be(true)
      expect(bill.reload.categories).to include(housing)

      # Switching it back on brings the option back, closing the loop.
      visit "/admin/categories"
      wait_until_loaded
      within("tr", text: "Housing") { click_button "Activate" }
      wait_until_loaded
      expect(page).to have_text("Category activated.")
      visit "/bills?sway_locale_id=#{sway_locale.id}"
      wait_until_loaded
      open_category_filter
      expect(page).to have_field("Housing", type: :checkbox)
    end
  end
end
