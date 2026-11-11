# frozen_string_literal: true

require "rails_helper"

# @lat: [[radix-select-keyboard-commit-race#The (role='option') technique unblocked a previously-skipped spec]]
RSpec.describe "Bill Creator category override", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) { create(:user, :sway_admin) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }

  before { create(:user_legislator, user: sway_admin_user, legislator: legislator) }

  it "adds and removes a category pill on the summary tab (60 R8)" do
    create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)
    create(:category, name: "Housing", slug: "housing", active: true)

    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{bill.id}/summary?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_text("No categories assigned yet", wait: 10)

    find("[aria-label='Add category']").click
    find("[role='option']", text: "Housing", wait: 10).click

    expect(page).to have_text("Category added", wait: 10)
    expect(page).to have_css("[aria-label='Remove Housing']", wait: 10)
    expect(BillCategory.find_by(bill_id: bill.id)).to be_present

    find("[aria-label='Remove Housing']").click

    expect(page).to have_text("Category removed", wait: 10)
    expect(page).to have_text("No categories assigned yet", wait: 10)
    expect(BillCategory.find_by(bill_id: bill.id)).to be_nil
  end
end
