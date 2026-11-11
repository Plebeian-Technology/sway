# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Supplemental Testimony",
  type: :system,
  js: true,
  phase16: true do
  include ActiveJob::TestHelper

  let(:admin_phone) { "4105551235" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }

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
    @sway_admin_user =
      create(:user, :registered, phone: admin_phone)
    create(:user_legislator, user: @sway_admin_user, legislator: legislator)
    ActiveJob::Base.queue_adapter = :test
  end

  after { cleanup_summary_files(bill) }

  it "allows entering supplemental testimony before generation" do
    create(:bill_llm_provisioning, :with_diff_content, bill: bill)

    sign_in_as(@sway_admin_user)
    navigate_to_positions_tab(bill)

    find("[data-testid='textarea-supplemental-testimony']").set(
      "This is additional testimony from the public hearing"
    )
    click_testid("btn-save-supplemental-testimony")

    navigate_to_summary_tab(bill)
    stub_pipeline_success(bill)
    click_testid("btn-generate-summary")

    expect(page).to have_css(
      "[data-testid='llm-status-badge']",
      text: "Queued…",
      wait: 10
    )

    expect(bill.bill_llm_provisioning.reload.supplemental_testimony).to include(
      "additional testimony"
    )
  end

  it "preserves supplemental testimony text in completed state" do
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      :completed,
      bill: bill,
      supplemental_testimony: "Previously entered testimony"
    )

    sign_in_as(@sway_admin_user)
    navigate_to_positions_tab(bill)

    testimony_textarea = find("[data-testid='textarea-supplemental-testimony']")
    expect(testimony_textarea.value).to include("Previously entered testimony")
  end

  # @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run]]
  it "turns org positions back on after testimony is pasted in" do
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      :completed,
      bill: bill,
      draft_org_positions: []
    )

    sign_in_as(@sway_admin_user)
    navigate_to_positions_tab(bill)

    # Nothing to draw positions from yet, and the screen says so rather than
    # showing an empty list — which is the difference between "none were found"
    # and "none could be looked for".
    expect(page).to have_css("[data-testid='llm-no-testimony']", wait: 10)

    find("[data-testid='textarea-supplemental-testimony']").set(
      "The r/baltimore Reddit community generally supports this legislation " \
      "since many of them are renters."
    )
    click_testid("btn-save-supplemental-testimony")

    # Saved testimony is what the job's positions gate reads, so wait for the
    # notice to go before buying a run — otherwise this example could pass or
    # fail on which request landed first.
    expect(page).to have_no_css("[data-testid='llm-no-testimony']", wait: 10)

    stub_pipeline_success(
      bill,
      org_positions: [
        {
          "org_name" => "r/baltimore Reddit community",
          "stance" => "support",
          "summary" => "The community supports the legislation because many of its members are renters."
        }
      ]
    )

    navigate_to_summary_tab(bill)
    click_testid("btn-regenerate-summary")
    click_testid("btn-confirm-dialog-confirm")

    # @lat: [[bill-creator-testimony-attachments#Polling updates attachment warnings without a page load]]
    expect(page).to have_css("[data-testid='llm-status-badge']", text: "Queued…", wait: 10)

    perform_enqueued_jobs(at: 1.day.from_now)
    perform_enqueued_jobs(at: 1.day.from_now)

    navigate_to_positions_tab(bill)

    # @lat: [[bill-creator-testimony-attachments#The clean attachment assertion is scoped to its component]]
    expect(page).to have_css(
      "[data-testid='org-position-card-r/baltimore-reddit-community-0']",
      wait: 20
    )
    expect(page).to have_text("r/baltimore Reddit community")

    # And it is a real draft on the row, not a card drawn from something the
    # browser was still holding.
    drafts = bill.bill_llm_provisioning.reload.draft_org_positions
    expect(drafts.length).to eq(1)
    expect(drafts.first["org_name"]).to eq("r/baltimore Reddit community")
    expect(drafts.first["stance"]).to eq("support")
  end

  it "includes supplemental testimony when regenerating" do
    create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

    sign_in_as(@sway_admin_user)
    navigate_to_positions_tab(bill)

    find("[data-testid='textarea-supplemental-testimony']").set(
      "New testimony for regeneration"
    )
    click_testid("btn-save-supplemental-testimony")

    navigate_to_summary_tab(bill)
    stub_pipeline_success(bill)
    click_testid("btn-regenerate-summary")

    click_testid("btn-confirm-dialog-confirm")

    expect(page).to have_css(
      "[data-testid='llm-status-badge']",
      text: "Queued…",
      wait: 10
    )

    expect(bill.bill_llm_provisioning.reload.supplemental_testimony).to include(
      "New testimony for regeneration"
    )
  end
end
