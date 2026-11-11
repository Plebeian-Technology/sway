# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Bill Creator form state", type: :system, js: true, phase16: true do
  # @type self: AdminBillCreatorFormStateSpecContext
  let(:admin_phone) { "4105550001" }
  let(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end
  let(:district) { create(:district, sway_locale:) }
  let(:legislator) { create(:legislator, district:) }
  let(:bill) do
    create(
      :bill,
      sway_locale:,
      legislator:,
      external_id: "NAV-FORM-STATE",
      title: "Form state browser test bill",
      category: "education",
      status: "committee",
      chamber: "council",
      link: "https://example.com/NAV-FORM-STATE",
      summary: "The persisted summary before the browser update."
    )
  end
  let(:organization) { create(:organization, sway_locale:, name: "NAV Form State Organization") }
  let(:position) do
    create(
      :organization_bill_position,
      bill:,
      organization:,
      support: "AGAINST",
      summary: "The persisted position summary."
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
    admin = create(:user, phone: admin_phone)
    address = create(:address, city: "baltimore", region_code: "MD", country: "United States")
    create(:user_address, user: admin, address:)
    create(:user_legislator, user: admin, legislator:)
    sign_in_as(admin)
    clear_browser_storage
  end

  # @lat: [[bill-creator-form-state#The summary field reads current form data#A browser save carries a programmatic summary update]]
  it "saves summary written through the mounted Details form without a textarea change" do
    bill
    external_summary = "Summary updated through the mounted Inertia form."
    visit "/admin/bill_creator/#{bill.id}/edit?event_key=bill&sway_locale_id=#{sway_locale.id}"
    expect(page).to have_button("Save Bill", wait: 20)

    page.execute_script(<<~JS, external_summary)
      const summary = document.querySelector('textarea[name="summary"]');
      if (!summary) throw new Error("The Details summary field is not mounted");

      const fiberKey = Object.keys(summary).find((key) => key.startsWith("__reactFiber$"));
      let fiber = fiberKey ? summary[fiberKey] : null;
      const forms = [];
      while (fiber) {
        const value = fiber.memoizedProps?.value;
        if (
          fiber.tag === 10 &&
          value &&
          typeof value.setData === "function" &&
          typeof value.transform === "function" &&
          typeof value.data?.summary === "string"
        ) {
          forms.push(value);
        }
        fiber = fiber.return;
      }
      if (forms.length !== 1) throw new Error(`Expected one mounted Details form provider, found ${forms.length}`);
      forms[0].setData("summary", arguments[0]);
    JS

    expect(page).to have_field("summary", with: external_summary, wait: 10)
    click_button "Save Bill"

    expect(page).to have_current_path(%r{/creator\?event_key=legislator_votes}, wait: 20)
    expect(page).to have_text("Bill Updated", wait: 10)
    expect(bill.reload.summary).to eq(external_summary)
  end

  # @lat: [[admin-organization-positions-browser-tests#Removing and re-adding restores unsaved position edits#Card removal restores the current organization draft]]
  it "restores edited organization values after card removal and re-addition" do
    position
    visit "/admin/bill_creator/#{bill.id}/creator?event_key=organizations&sway_locale_id=#{sway_locale.id}"
    expect(page).to have_field("NAV Form State Organization position summary", with: "The persisted position summary.", wait: 20)

    page.execute_script(<<~JS, position.id)
      const positionId = arguments[0];
      window.__billCreatorPositionDeletes = [];
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url, ...rest) {
        const target = new URL(String(url), window.location.href);
        if (String(method).toUpperCase() === "DELETE" && target.pathname === `/organization_bill_positions/${positionId}`) {
          window.__billCreatorPositionDeletes.push(target.pathname);
        }
        return originalOpen.call(this, method, url, ...rest);
      };
    JS

    fill_in "NAV Form State Organization position summary", with: "Unsaved card-path summary"
    find("[role='switch'][aria-label='NAV Form State Organization support']").click
    expect(find("[role='switch'][aria-label='NAV Form State Organization support']")["aria-checked"]).to eq("true")

    click_testid "btn-remove-org-0"
    expect(page).to have_text("Removed NAV Form State Organization from NAV-FORM-STATE.", wait: 20)
    expect(page.evaluate_script("window.__billCreatorPositionDeletes.length")).to eq(1)
    expect(position.reload.active?).to be(false)

    picker = find("input[placeholder='Search or create an organization...']")
    picker.set(organization.name)
    click_button organization.name

    expect(page).to have_field("NAV Form State Organization position summary", with: "Unsaved card-path summary", wait: 10)
    expect(find("[role='switch'][aria-label='NAV Form State Organization support']")["aria-checked"]).to eq("true")
  end

  # @lat: [[admin-organization-positions-browser-tests#Removing and re-adding restores unsaved position edits#Chip removal restores the current organization draft]]
  it "restores edited organization values after chip removal and re-addition" do
    position
    visit "/admin/bill_creator/#{bill.id}/positions?sway_locale_id=#{sway_locale.id}"
    expect(page).to have_field("NAV Form State Organization position summary", with: "The persisted position summary.", wait: 20)

    page.execute_script(<<~JS, position.id)
      const positionId = arguments[0];
      window.__billCreatorPositionDeletes = [];
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url, ...rest) {
        const target = new URL(String(url), window.location.href);
        if (String(method).toUpperCase() === "DELETE" && target.pathname === `/organization_bill_positions/${positionId}`) {
          window.__billCreatorPositionDeletes.push(target.pathname);
        }
        return originalOpen.call(this, method, url, ...rest);
      };
    JS

    fill_in "NAV Form State Organization position summary", with: "Unsaved chip-path summary"
    find("[role='switch'][aria-label='NAV Form State Organization support']").click
    expect(find("[role='switch'][aria-label='NAV Form State Organization support']")["aria-checked"]).to eq("true")

    find("button[aria-label='Remove NAV Form State Organization']").click
    expect(page).to have_text("Removed NAV Form State Organization from NAV-FORM-STATE.", wait: 20)
    expect(page.evaluate_script("window.__billCreatorPositionDeletes.length")).to eq(1)
    expect(position.reload.active?).to be(false)

    picker = find("input[placeholder='Search or create an organization...']")
    picker.set(organization.name)
    click_button organization.name

    expect(page).to have_field("NAV Form State Organization position summary", with: "Unsaved chip-path summary", wait: 10)
    expect(find("[role='switch'][aria-label='NAV Form State Organization support']")["aria-checked"]).to eq("true")
  end
end
