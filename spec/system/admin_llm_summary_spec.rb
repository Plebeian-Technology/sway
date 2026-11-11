# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin LLM Summary Generation",
  type: :system,
  js: true,
  phase16: true do
  include ActiveJob::TestHelper

  let(:admin_phone) { "4105551234" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  # @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Independent inputs for summaries and positions]]
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      extracted_text: "Section 1. The Mayor shall submit an annual report."
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
    @sway_admin_user =
      create(:user, :registered, phone: admin_phone)
    create(:user_legislator, user: @sway_admin_user, legislator: legislator)
    ActiveJob::Base.queue_adapter = :test
  end

  after { cleanup_summary_files(bill) }

  it "displays not-generated state for bill with pipeline data but no generation" do
    create(:bill_llm_provisioning, :with_diff_content, bill: bill)

    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css(
      "[data-testid='llm-status-badge']",
      text: "Not generated"
    )
    expect(page).to have_css(
      "[data-testid='btn-generate-summary']",
      text: "Generate summary"
    )
  end

  it "transitions from not-generated to queued after clicking Generate Summary" do
    create(:bill_llm_provisioning, :with_diff_content, bill: bill)

    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    stub_pipeline_success(bill)

    click_testid("btn-generate-summary")

    expect(page).to have_css(
      "[data-testid='llm-status-badge']",
      text: "Queued…",
      wait: 10
    )
  end

  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the tab says about a run it did not finish]]
  it "says a run is queued, and not only in a badge, after clicking Generate" do
    create(:bill_llm_provisioning, :with_diff_content, bill: bill)

    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    stub_pipeline_success(bill)

    click_testid("btn-generate-summary")

    expect(page).to have_css(
      "[data-testid='llm-queued-run-notice']",
      text: /queued/i,
      wait: 10
    )
  end

  it "transitions to ready and shows summary after job completes" do
    create(:bill_llm_provisioning, :with_diff_content, bill: bill)

    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    stub_pipeline_success(bill, summary_text: "Generated test summary")

    click_testid("btn-generate-summary")

    expect(page).to have_css(
      "[data-testid='llm-status-badge']",
      text: "Queued…",
      wait: 10
    )

    # GenerateBillSummaryJob submits the work, then schedules itself again
    # (with wait:) to check whether it has finished. Run both jobs: passing an
    # `at:` far in the future makes the delayed check run too.
    perform_enqueued_jobs(at: 1.day.from_now)
    perform_enqueued_jobs(at: 1.day.from_now)

    expect(page).to have_css(
      "[data-testid='llm-status-badge']",
      text: "Ready",
      wait: 15
    )
    expect(page).to have_css("[data-testid='textarea-llm-summary']")
  end

  it "shows completed state with editable summary and breakdown toggle" do
    create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css("[data-testid='llm-status-badge']", text: "Ready")
    expect(page).to have_css("[data-testid='textarea-llm-summary']")
    expect(page).to have_css("[data-testid='btn-save-summary']")

    click_testid("btn-toggle-breakdown")

    expect(page).to have_css("[data-testid='llm-full-breakdown']")
    expect(page).to have_css("[data-testid='btn-regenerate-summary']")
  end

  it "shows no-pipeline-data state when the bill has no provisioning row" do
    # @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Independent inputs for summaries and positions]]
    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css("[data-testid='llm-no-pipeline-data']")
  end
end
