# frozen_string_literal: true

require "rails_helper"

# @lat: [[query-parameter-navigation-carry#Centralized interception mechanism]]
# @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
# @lat: [[query-parameter-navigation-carry#Excluded route constants and security boundaries]]
# @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]
RSpec.describe "App-wide query parameter navigation carry", type: :system, js: true do
  let(:admin_phone) { "4105550001" }
  let(:address) { create(:address, city: "baltimore", region_code: "MD", country: "United States") }
  let(:sway_locale) { address.sway_locales.find { |l| l.city == "baltimore" } }
  let(:other_locale) { address.sway_locales.find { |l| l.city == "maryland" } }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:other_district) { create(:district, sway_locale: other_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:other_legislator) { create(:legislator, district: other_district) }
  let(:sway_admin_user) { create(:user, :registered, phone: admin_phone) }

  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Legislation Automation Act",
      scheduled_release_date_utc: 2.days.ago,
      introduced_date_time_utc: 10.days.ago
    )
  end

  let(:run_1) do
    create(
      :legislation_pipeline_run,
      bill: bill,
      sway_locale: sway_locale,
      status: "succeeded",
      created_at: 2.hours.ago,
      completed_at: 1.hour.ago
    )
  end

  let(:run_2) do
    create(
      :legislation_pipeline_run,
      bill: bill,
      sway_locale: sway_locale,
      status: "succeeded",
      created_at: 30.minutes.ago,
      completed_at: 20.minutes.ago
    )
  end

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

  before do
    create(:user_address, user: sway_admin_user, address: address)
    create(:user_legislator, user: sway_admin_user, legislator: legislator)
    create(:user_legislator, user: sway_admin_user, legislator: other_legislator)

    run_1
    run_2

    sign_in_as(sway_admin_user)
    page.execute_script("window.localStorage && window.localStorage.clear(); " \
                        "window.sessionStorage && window.sessionStorage.clear();")
  end

  it "leg 1: paste a link carrying state into a fresh window and get that state back" do
    visit "/bills?sway_locale_id=#{sway_locale.id}&bills_sort=title&bills_direction=asc"
    wait_until_loaded

    expect(page).to have_current_path(%r{/bills.*sway_locale_id=#{sway_locale.id}}, wait: 10)
    expect(page).to have_current_path(/bills_sort=title/)
    expect(page).to have_current_path(/bills_direction=asc/)

    page.execute_script("document.querySelector('a[href*=\"/legislators\"]').click()")
    wait_until_loaded
    expect(page).to have_current_path(%r{/legislators.*sway_locale_id=#{sway_locale.id}}, wait: 10)
    expect(page).to have_no_current_path(/bills_sort=/)
  end

  it "leg 2: clear the run selector to latest and prove run_id stays gone across a tab change" do
    visit "/admin/bill_creator/#{bill.id}/pipeline?run_id=#{run_1.id}&sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_current_path(/run_id=#{run_1.id}/, wait: 10)
    expect(find("[data-testid='run-selector']").value).to eq(run_1.id.to_s)

    find("[data-testid='run-selector'] option[value='']").select_option
    wait_until_loaded
    expect(page).to have_no_current_path(/run_id=/, wait: 10)

    click_on "Summary"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/summary}, wait: 10)
    expect(page).to have_no_current_path(/run_id=/)
  end

  it "leg 3: let a one-shot highlight fire and prove it does not return on the next navigation" do
    visit "/admin/bill_creator/#{bill.id}/pipeline?highlight=#{run_1.id}&sway_locale_id=#{sway_locale.id}"
    wait_until_loaded
    expect(page).to have_no_current_path(/highlight=\d+/, wait: 10)

    click_on "Summary"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/summary}, wait: 10)
    expect(page).to have_no_current_path(/highlight/)

    click_on "Pipeline & LLM"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/pipeline}, wait: 10)
    expect(page).to have_no_current_path(/highlight/)

    find("[role='tab']", text: "Bill Creator").click
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/creator}, wait: 10)
    expect(page).to have_no_current_path(/highlight/)

    fill_in "Bill Title", with: "Saved after highlight clearance"
    click_on "Save Bill"

    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/creator\?event_key=legislator_votes}, wait: 20)
    expect(page).to have_no_current_path(/highlight/)
    expect(page).to have_text("Bill Updated", wait: 10)
    expect(bill.reload.title).to eq("Saved after highlight clearance")
  end

  it "leg 4: switch locale and prove page drops" do
    visit "/legislators?sway_locale_id=#{sway_locale.id}&page=2"
    wait_until_loaded
    expect(page).to have_current_path(/sway_locale_id=#{sway_locale.id}/, wait: 10)
    expect(page).to have_current_path(/page=2/)

    find_by_id("v2-locale").find("option[value='#{other_locale.id}']").select_option
    wait_until_loaded
    expect(page).to have_current_path(/sway_locale_id=#{other_locale.id}/, wait: 10)
    expect(page).to have_no_current_path(/page=/)
  end

  it "leg 5: pin a run in the run selector, change Bill Creator tab, and prove the run parameter is still on the address and the pinned run is still selected" do
    visit "/admin/bill_creator/#{bill.id}/pipeline?run_id=#{run_1.id}&sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_current_path(/run_id=#{run_1.id}/, wait: 10)
    expect(find("[data-testid='run-selector']").value).to eq(run_1.id.to_s)

    click_on "Summary"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/summary}, wait: 10)
    expect(page).to have_current_path(/run_id=#{run_1.id}/)

    click_on "Pipeline & LLM"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/pipeline}, wait: 10)
    expect(page).to have_current_path(/run_id=#{run_1.id}/)
    expect(find("[data-testid='run-selector']").value).to eq(run_1.id.to_s)
  end

  it "leg 6: deselect all pipeline stages, verify request retains empty selection, and reload keeps zero stages" do
    visit "/admin/bill_creator/#{bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_css("[data-testid='stage-selection-count']", text: "7 of 8 selected", wait: 10)

    find("[data-testid='clear-all-stages']").click
    wait_until_loaded

    expect(page).to have_current_path(/selected_stages=/, wait: 10)
    expect(find("[data-testid='stage-selection-count']").text).to eq("0 of 8 selected")

    page.driver.browser.navigate.refresh
    wait_until_loaded
    expect(page).to have_current_path(/selected_stages=/, wait: 10)
    expect(find("[data-testid='stage-selection-count']").text).to eq("0 of 8 selected")

    find("[data-testid='select-all-stages']").click
    wait_until_loaded
    expect(find("[data-testid='stage-selection-count']").text).to eq("8 of 8 selected")
  end

  # @lat: [[bill-creator-shell#Why the Bill Creator carries query parameters across navigation]]
  it "leg 7: carry pipeline stage selection and operator controls across Bill Creator tabs" do
    visit "/admin/bill_creator/#{bill.id}/pipeline?selected_stages[]=fetch-bills&selected_stages[]=fetch-law&download_missing_assets=0&severity=error&window=1d&run_id=#{run_1.id}&sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_current_path(%r{selected_stages.*fetch-bills}, wait: 10)
    expect(page).to have_current_path(/download_missing_assets=0/)
    expect(page).to have_current_path(/severity=error/)
    expect(page).to have_current_path(/window=1d/)
    expect(page).to have_current_path(/run_id=#{run_1.id}/)

    click_on "Summary"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/summary}, wait: 10)
    expect(page).to have_current_path(%r{selected_stages.*fetch-bills})
    expect(page).to have_current_path(%r{selected_stages.*fetch-law})
    expect(page).to have_current_path(/download_missing_assets=0/)
    expect(page).to have_current_path(/severity=error/)
    expect(page).to have_current_path(/window=1d/)
    expect(page).to have_current_path(/run_id=#{run_1.id}/)

    click_on "Pipeline & LLM"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{bill.id}/pipeline}, wait: 10)
    expect(page).to have_current_path(%r{selected_stages.*fetch-bills})
    expect(page).to have_current_path(%r{selected_stages.*fetch-law})
    expect(page).to have_current_path(/download_missing_assets=0/)
    expect(page).to have_current_path(/severity=error/)
    expect(page).to have_current_path(/window=1d/)
    expect(page).to have_current_path(/run_id=#{run_1.id}/)
  end
end
