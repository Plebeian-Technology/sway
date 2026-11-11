# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-pipeline-controls-panel#Why stage selection uses two buttons rather than a tick-all box]]
RSpec.describe "Admin pipeline stage selection",
  type: :system,
  js: true,
  phase55: true do
  let(:admin_phone) { "4105550055" }
  let(:sway_locale) do
    SwayLocale.find_by(
      city: "baltimore",
      state: "MD",
      country: "United States"
    ) ||
      create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) do
    create(:user, :registered, phone: admin_phone)
  end

  # A bill with no extracted text and no parsed sections. It is the subject
  # missing artifacts for the prerequisite warning (Behavior 3), and for the
  # extra stages that missing artifacts pull in (Behavior 1).
  let(:deficient_bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      extracted_text: nil
    )
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
    # Stop the real RunLegislationPipelineJob from being enqueued — this spec
    # checks what gets saved for the run, not the orchestrator actually running.
    allow(RunLegislationPipelineJob).to receive(:perform_later)
  end

  # @lat: [[bill-creator-pipeline-controls-panel#Pipeline actions preserve the working address]]
  it "persists run.stages and run.download_missing_assets from operator selection (dma=true default)" do
    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{deficient_bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_css("[data-testid='checkbox-stage-fetch-bills']", wait: 10)
    expect(page).to have_css("[data-testid='checkbox-stage-summarize-bill'][data-state='unchecked']")

    find("[data-testid='checkbox-stage-fetch-bills']").click
    # @lat: [[bill-creator-pipeline-controls-panel#Why pending state caches prevent click loss during round trips]]
    expect(page).to have_css("[data-testid='checkbox-stage-fetch-bills'][data-state='unchecked']")
    find("[data-testid='checkbox-stage-fetch-hearings']").click
    expect(page).to have_css("[data-testid='checkbox-stage-fetch-hearings'][data-state='unchecked']")

    expect(page).to have_css("[data-testid='checkbox-download-missing-assets']")

    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
    before_count = LegislationPipelineRun.count
    find("[data-testid='btn-run-pipeline']").click
    wait_until { LegislationPipelineRun.count == before_count + 1 }
    expect(LegislationPipelineRun.count).to eq(before_count + 1)

    run = LegislationPipelineRun.order(:id).last!
    expect(run.stages).not_to include("fetch-bills")
    expect(run.stages).not_to include("fetch-hearings")
    expect(run.stages).not_to include("summarize-bill")
    expect(run.stages).to include("parse-sections", "fetch-law", "extract-text", "generate-diffs", "clean-testimony")
    # The server recomputes this: both fetch stages were UNchecked, so
    # download_missing_assets keeps the admin's value (checked by default, so
    # true).
    expect(run.download_missing_assets).to be(true)
  end

  # @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]
  it "clears every stage in one click, and the run keeps only what is ticked afterwards" do
    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{deficient_bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    # @lat: [[partial-reload-poll-lists#Why the Bill Creator tuples are read out of the TypeScript]]
    stage_count = Pipeline::StageKeys::KEY_TO_SYMBOL.size

    expect(page).to have_css("[data-testid='select-all-stages']:not([disabled])", wait: 10)
    expect(page).to have_css(
      "[data-testid='stage-selection-count']", text: "#{stage_count - 1} of #{stage_count} selected"
    )

    find("[data-testid='clear-all-stages']").click

    # @lat: [[bill-creator-pipeline-controls-panel#Why stage selection uses two buttons rather than a tick-all box]]
    Pipeline::StageKeys::KEY_TO_SYMBOL.each_key do |key|
      expect(page).to have_css("[data-testid='checkbox-stage-#{key}'][data-state='unchecked']")
    end
    expect(page).to have_css("[data-testid='stage-selection-count']", text: "0 of #{stage_count} selected")
    expect(find("[data-testid='clear-all-stages']")["disabled"]).to be_truthy
    expect(find("[data-testid='btn-run-pipeline']")["disabled"]).to be_truthy

    find("[data-testid='checkbox-stage-fetch-hearings']").click
    expect(page).to have_css("[data-testid='checkbox-stage-fetch-hearings'][data-state='checked']")
    expect(page).to have_css("[data-testid='stage-selection-count']", text: "1 of #{stage_count} selected")
    expect(page).to have_css("[data-testid='btn-run-pipeline']:not([disabled])")
    # Wait for the 250ms URL push debounce to settle so the debounced visit does not race the run POST
    sleep 0.3

    before_count = LegislationPipelineRun.count
    find("[data-testid='btn-run-pipeline']").click
    wait_until { LegislationPipelineRun.count == before_count + 1 }

    run = LegislationPipelineRun.order(:id).last!
    # THE ASSERTION THAT MATTERS: one stage, not every stage. If the empty list
    # were read as "everything" again, this row would carry all of them.
    expect(run.stages).to eq(["fetch-hearings"])
  end

  # @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#Why stage selection uses two buttons rather than a tick-all box#An auto-included stage does less than the same stage ticked]]
  it "renders the download_missing_assets toggle as disabled when both fetches are checked" do
    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{deficient_bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    toggle = find("[data-testid='checkbox-download-missing-assets']", wait: 10)
    # Capybara's `disabled?` reads the aria-disabled or disabled attribute on
    # the rendered checkbox button; the shadcn Checkbox sets the plain HTML
    # `disabled` attribute when its prop is true.
    expect(toggle["disabled"]).to be_truthy
  end

  # @lat: [[bill-creator-pipeline-controls-panel#Why stage selection uses two buttons rather than a tick-all box]]
  it "renders the WA-01 prereq warn alert when dma=false leaves prerequisites unsatisfied" do
    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{deficient_bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    # Uncheck both fetch stages so the toggle becomes usable — with both of
    # them checked, it is disabled. Asserting the disabled state FIRST is what
    # makes the enabled assertion below meaningful: if the selector could not
    # tell the two apart, this line would fail rather than passing vacuously.
    expect(page).to have_css("[data-testid='checkbox-download-missing-assets'][disabled]")

    find("[data-testid='checkbox-stage-fetch-bills']").click
    expect(page).to have_css("[data-testid='checkbox-stage-fetch-bills'][data-state='unchecked']")
    find("[data-testid='checkbox-stage-fetch-hearings']").click
    expect(page).to have_css("[data-testid='checkbox-stage-fetch-hearings'][data-state='unchecked']")

    toggle = find("[data-testid='checkbox-download-missing-assets']")
    # @lat: [[bill-creator-pipeline-controls-panel#Why stage selection uses two buttons rather than a tick-all box]]
    expect(page).to have_css("[data-testid='checkbox-download-missing-assets']:not([disabled])")
    # Now click to UNCHECK download_missing_assets. The warning should appear,
    # because deficient_bill has no extracted_text, so parse-sections is
    # missing something it needs — which is what Pipeline::ArtifactPresence
    # reports.
    toggle.click

    # The warning renders with the agreed wording, word for word (the regex
    # insists on "will FAIL" — never softened to "may fail").
    expect(page).to have_css("[data-testid='pipeline-prereq-warn-alert']", wait: 10)

    # The agreed wording, word for word: "{N} bills will FAIL {stage} because
    # they have no {artifact} — enable Download missing assets or check {prereq}"
    within("[data-testid='pipeline-prereq-warn-alert']") do
      expect(page).to have_text(
        /\d+ bills will FAIL .+ because they have no .+ — enable Download missing assets or check /
      )
    end
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  it "resume preserves parent_run.stages and parent_run.download_missing_assets" do
    failed_run = create(
      :legislation_pipeline_run,
      bill: deficient_bill,
      stages: ["parse-sections", "summarize-bill"],
      download_missing_assets: false,
      status: "failed"
    )

    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{deficient_bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_css("[data-testid='btn-resume-pipeline']", wait: 10)

    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
    before_count = LegislationPipelineRun.count
    find("[data-testid='btn-resume-pipeline']").click
    wait_until { LegislationPipelineRun.count == before_count + 1 }
    expect(LegislationPipelineRun.count).to eq(before_count + 1)

    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    child = LegislationPipelineRun.where(parent_run_id: failed_run.id.to_s).order(:id).last!
    expect(child).not_to be_nil
    # Resume copies the parent's download_missing_assets exactly.
    expect(child.download_missing_assets).to eq(failed_run.download_missing_assets)
    # Resume copies the parent's stages exactly — whatever the admin ticked.
    expect(child.stages).to eq(failed_run.stages)
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Restart rejects indeterminate runs without a locale]]
  it "restart spawns a child run that inherits parent.stages and parent.download_missing_assets" do
    failed_run = create(
      :legislation_pipeline_run,
      bill: deficient_bill,
      stages: ["parse-sections", "summarize-bill"],
      # @lat: [[legislation-pipeline#Runs, resume and restart]]
      download_missing_assets: false,
      status: "failed",
      completed_at: 1.hour.ago
    )

    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{deficient_bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_css("[data-testid='btn-restart-pipeline']", wait: 10)

    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
    before_count = LegislationPipelineRun.count
    find("[data-testid='btn-restart-pipeline']").click
    wait_until { LegislationPipelineRun.count == before_count + 1 }
    expect(LegislationPipelineRun.count).to eq(before_count + 1)

    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    child = LegislationPipelineRun.where(parent_run_id: failed_run.id.to_s).order(:id).last!
    expect(child).not_to be_nil
    # origin distinguishes this restart child from Behavior 4's resume child.
    expect(child.origin).to eq("restart")
    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    expect(child.download_missing_assets).to eq(failed_run.download_missing_assets)
    expect(child.download_missing_assets).to be(false)
    expect(child.stages).to eq(failed_run.stages)
  end
end
