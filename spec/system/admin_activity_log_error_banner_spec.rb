# frozen_string_literal: true

require "rails_helper"

# @lat: [[activity-log-flash-transport#The activity log's flash transport#Why the fallback is tested without a real overflow]]
RSpec.describe "Admin activity log error banner",
  type: :system,
  js: true,
  phase16: true do
  let(:admin_phone) { "4105550018" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }
  let(:sway_admin_user) do
    create(:user, :registered, phone: admin_phone)
  end

  around do |example|
    previous_admin_phones = User::ADMIN_PHONES.dup

    begin
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])

      example.run
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, previous_admin_phones)
    end
  end

  before do
    create(:user_legislator, user: sway_admin_user, legislator: legislator)
    create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)
  end

  it "renders the destructive banner with an entry-link that stays on the current pipeline tab" do
    sign_in_as(sway_admin_user)
    # Visiting the probe sets flash[:activity_log_error] and redirects to the
    # bill edit page; Capybara follows the redirect. inertia_share carries the
    # flash into usePage().props.flash when that page renders, so
    # ActivityLogPanel sees activity_log_error and draws the banner.
    visit "/__inertia_flash_error_probe/trigger?bill_id=#{bill.id}"
    wait_until_loaded

    # (a) The banner renders in its red, destructive style.
    expect(page).to have_css(
      "[data-testid='activity-log-error-banner']",
      wait: 10
    )

    # @lat: [[activity-log-flash-transport#The activity log's flash transport#Why the fallback is tested without a real overflow]]
    href = within("[data-testid='activity-log-error-banner']") do
      find("a")["href"]
    end
    expect(href).to include("/admin/bill_creator/#{bill.id}/pipeline")
    expect(href).to match(/highlight=\d+/)
    expect(href).not_to include("tab_key=")

    # (c) The error class shows up in the banner text, so whoever is on call
    # can match it to the WARN log line Transport.dispatch_inertia writes.
    expect(page).to have_text("SyntheticTestError")
  end
end
