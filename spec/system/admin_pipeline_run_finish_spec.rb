# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-summary-tab#Why the no-provisioning poll runs out]]
RSpec.describe "Admin pipeline run finishing", type: :system, js: true do
  let(:admin_phone) { "4105551241" }
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

  before { create(:user_legislator, user: sway_admin_user, legislator: legislator) }

  after { cleanup_summary_files(bill) }

  # @lat: [[bill-creator-summary-tab#Why the no-provisioning poll runs out]]
  it "clears the pipeline-busy notice when the run finishes, with no reload" do
    create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)
    run = create(:legislation_pipeline_run, :running, bill: bill)

    sign_in_as(sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css(
      "[data-testid='bill-pipeline-refresh-status']",
      wait: 10
    )
    expect(page).to have_text(
      "Generation is unavailable until this pipeline run finishes"
    )

    run.mark_succeeded!
    expect(LegislationPipelineRun.active_for_bill(bill)).to be_empty

    expect(page).to have_no_css(
      "[data-testid='bill-pipeline-refresh-status']",
      wait: 20
    )
  end

  # @lat: [[bill-creator-summary-tab#Why the no-provisioning poll runs out]]
  it "clears the notice even when the live message never arrives" do
    create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)
    run = create(:legislation_pipeline_run, :running, bill: bill)

    sign_in_as(sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css(
      "[data-testid='bill-pipeline-refresh-status']",
      wait: 10
    )

    run.update_columns(status: "succeeded", completed_at: Time.current)
    expect(LegislationPipelineRun.active_for_bill(bill)).to be_empty

    expect(page).to have_no_css(
      "[data-testid='bill-pipeline-refresh-status']",
      wait: 20
    )
  end

  # @lat: [[bill-creator-summary-tab#Why the no-provisioning poll runs out]]
  it "clears the notice after moving from the Pipeline tab to the Summary tab" do
    create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)
    run = create(:legislation_pipeline_run, :running, bill: bill)

    sign_in_as(sway_admin_user)
    navigate_to_pipeline_llm_tab(bill)

    click_button "Summary"

    expect(page).to have_css(
      "[data-testid='bill-pipeline-refresh-status']",
      wait: 10
    )

    run.update_columns(status: "succeeded", completed_at: Time.current)

    expect(page).to have_no_css(
      "[data-testid='bill-pipeline-refresh-status']",
      wait: 20
    )
  end
end
