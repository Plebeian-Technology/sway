# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the staleness marker quotes]]
RSpec.describe "Admin summary stale marker", type: :system, js: true do
  include ActiveJob::TestHelper

  let(:admin_phone) { "4105551244" }
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
    ActiveJob::Base.queue_adapter = :test
  end

  after { cleanup_summary_files(bill) }

  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the staleness marker quotes]]
  def up_to_date_summary
    create(
      :bill_llm_provisioning,
      :completed,
      bill: bill,
      diff_content: "# Test diff",
      diff_generated_at: 2.hours.ago,
      llm_generated_at: 1.hour.ago,
      extracted_testimony: "Testimony submitted at the first hearing.",
      testimony_fetched_at: 90.minutes.ago
    )
  end

  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Why the no-provisioning poll runs out]]
  it "raises the out-of-date marker on its own when newer testimony lands" do
    provisioning = up_to_date_summary
    create(:legislation_pipeline_run, :running, bill: bill)

    sign_in_as(sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css("[data-testid='bill-pipeline-refresh-status']", wait: 10)
    expect(page).to have_no_css("[data-testid='llm-stale-header']")

    plant_reload_probe!

    # What fetch-hearings does when it finds newer testimony: the text and the
    # moment, written together.
    provisioning.update!(
      extracted_testimony: "Testimony submitted at the first hearing. And more, from the second.",
      testimony_fetched_at: Time.current
    )

    expect(page).to have_css("[data-testid='llm-stale-header']", wait: 20)

    # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the staleness marker quotes]]
    within("[data-testid='llm-stale-chip']") do
      expect(page).to have_text("testimony")
      expect(page).to have_no_text("pipeline data")
    end

    # Nothing was pressed and nothing navigated.
    expect_no_full_page_load!
  end

  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the staleness marker quotes]]
  it "clears the marker once the summary is made again" do
    provisioning = up_to_date_summary
    provisioning.update!(testimony_fetched_at: Time.current)

    sign_in_as(sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css("[data-testid='llm-stale-header']", wait: 10)

    plant_reload_probe!

    stub_pipeline_success(bill, summary_text: "Summary made again from the newer testimony")

    # On an out-of-date row this is the ONLY regenerate button: the completed
    # view hides its own with `{!stale && …}`.
    click_testid("btn-regenerate-from-latest-data")
    click_testid("btn-confirm-dialog-confirm")

    # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the tab says about a run it did not finish]]
    expect(page).to have_css("[data-testid='llm-status-badge']", text: "Queued…", wait: 10)

    # The job submits the work and then re-schedules itself to check whether it
    # finished, so both have to run — an `at:` in the future reaches the
    # delayed one.
    perform_enqueued_jobs(at: 1.day.from_now)
    perform_enqueued_jobs(at: 1.day.from_now)

    expect(page).to have_no_css("[data-testid='llm-stale-header']", wait: 20)
    expect(page).to have_css("[data-testid='llm-status-badge']", text: "Ready")

    # The flag really moved, rather than the header being hidden for some other
    # reason — the marker and the row have to agree.
    expect(provisioning.reload.stale?).to be(false)

    expect_no_full_page_load!
  end
end
