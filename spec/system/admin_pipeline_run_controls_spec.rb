# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Admin controls are exercised through the browser]]
RSpec.describe "Admin pipeline run controls", type: :system, js: true, phase16: true do
  let(:admin_phone) { "4105550019" }
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
  end

  it "force-fails an in-flight run via the type-to-confirm dialog" do
    run = create(:legislation_pipeline_run, :running, bill: bill)

    sign_in_as(sway_admin_user)
    navigate_to_pipeline_llm_tab(bill)

    # The force-fail button only appears while a run exists and is running.
    find("[data-testid='btn-force-fail']", wait: 10).click

    within("[data-testid='force-fail-dialog']") do
      # The server only accepts the exact phrase "force fail". Typing it turns
      # on the confirm button.
      find("[data-testid='input-force-fail-confirm']").set("force fail")
      expect(page).to have_button("Force fail", disabled: false)
      find("[data-testid='btn-force-fail-confirm']").click
    end

    # Once the run stops running, the buttons for in-flight runs go away.
    expect(page).to have_no_css("[data-testid='btn-force-fail']", wait: 10)
    expect(run.reload.status).to eq("failed")
  end

  it "sweeps stale (non-terminal) runs to failed via the sweep button" do
    allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?).and_return(false)
    stale_running = create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago, updated_at: 5.hours.ago)
    stale_queued = create(:legislation_pipeline_run, status: "queued", created_at: 10.hours.ago, updated_at: 10.hours.ago)

    sign_in_as(sway_admin_user)
    navigate_to_pipeline_llm_tab(bill)

    # The sweep button only appears when at least one stale run exists.
    find("[data-testid='btn-sweep-stale-pipeline-runs']", wait: 10).click

    # Sweep asks for confirmation with the app's own React dialog, not the
    # browser's built-in window.confirm. So accept it by clicking the
    # "Mark failed" button, the same way the orphan-delete spec does.
    within("[role='dialog']") { click_button("Mark failed") }

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The sweep assertion follows persisted run state]]
    [stale_running, stale_queued].each do |run|
      Timeout.timeout(15) do
        loop do
          break if run.reload.status == "failed"
          sleep 0.1
        end
      end
    end

    expect(stale_running.reload.status).to eq("failed")
    expect(stale_queued.reload.status).to eq("failed")
  end
end
