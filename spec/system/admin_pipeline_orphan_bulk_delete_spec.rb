# frozen_string_literal: true

require "rails_helper"

# @lat: [[admin-pipeline-orphan-bulk-delete#The browser follows the complete delete loop]]
RSpec.describe "Admin pipeline orphan bulk delete",
  type: :system,
  js: true,
  phase16: true do
  let(:admin_phone) { "4105550017" }
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
    # @lat: [[admin-pipeline-orphan-bulk-delete#Orphan rows are deterministic in the test database]]
    allow_any_instance_of(LegislationPipelineRun) # rubocop:disable RSpec/AnyInstance
      .to receive(:orphan?).and_return(true)
  end

  it "renders the orphan delete button, prompts confirm, hard-deletes rows, and hides button after success" do
    orphan_a = create(:legislation_pipeline_run,
      status: "running", created_at: 5.hours.ago)
    orphan_b = create(:legislation_pipeline_run,
      status: "queued", created_at: 10.hours.ago)

    sign_in_as(sway_admin_user)
    navigate_to_pipeline_llm_tab(bill)

    # Button visible (orphan_pipeline_run_count = 2).
    expect(page).to have_css(
      "[data-testid='btn-delete-orphan-pipeline-runs']",
      wait: 10
    )
    expect(page).to have_text("Delete 2 orphan runs")

    # @lat: [[admin-pipeline-orphan-bulk-delete#The app dialog is the confirmation surface]]
    find("[data-testid='btn-delete-orphan-pipeline-runs']").click
    within("[role='dialog']") { click_button("Delete orphans") }

    # @lat: [[admin-pipeline-orphan-bulk-delete#Wait for the rendered count to reach zero]]
    expect(page).to have_no_css(
      "[data-testid='btn-delete-orphan-pipeline-runs']",
      wait: 10
    )

    expect(LegislationPipelineRun.exists?(orphan_a.id)).to be false
    expect(LegislationPipelineRun.exists?(orphan_b.id)).to be false
    expect(LegislationPipelineRun.count).to eq(0)
  end

  it "dismissing the confirm dialog is a no-op (no DELETE fires)" do
    create(:legislation_pipeline_run,
      status: "running", created_at: 5.hours.ago)

    sign_in_as(sway_admin_user)
    navigate_to_pipeline_llm_tab(bill)

    expect(page).to have_css(
      "[data-testid='btn-delete-orphan-pipeline-runs']",
      wait: 10
    )

    expect {
      find("[data-testid='btn-delete-orphan-pipeline-runs']").click
      # Close the React confirmation dialog with its Cancel button; there is no
      # browser-native confirm for dismiss_confirm to drive.
      within("[role='dialog']") { click_button("Cancel") }
      # A short wait, so that a delete that wrongly went out would arrive
      # before we check; the assertion is that nothing changed.
      wait_until_loaded
    }.not_to change(LegislationPipelineRun, :count)

    # Button still visible (orphan count unchanged).
    expect(page).to have_css(
      "[data-testid='btn-delete-orphan-pipeline-runs']"
    )
  end
end
