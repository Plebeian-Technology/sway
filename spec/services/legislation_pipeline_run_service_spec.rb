require "rails_helper"

# The :vcr tag puts this spec on the record-and-replay path. Today's
# examples make no outgoing calls; it's here so a future one that does
# replays from spec/cassettes/ automatically.
RSpec.describe LegislationPipelineRunService, :vcr do
  let(:sway_locale) { create(:sway_locale, :baltimore) }

  describe "#call" do
    it "creates a LegislationPipelineRun row in queued state and enqueues RunLegislationPipelineJob" do
      service = described_class.new(stages: ["fetch-bills"], sway_locale: sway_locale)
      expect { service.call }
        .to change(LegislationPipelineRun, :count).by(1)
        .and have_enqueued_job(RunLegislationPipelineJob)
      run = LegislationPipelineRun.last
      expect(run.status).to eq("queued")
      expect(run&.sway_locale_id).to eq(sway_locale.id)
    end

    it "refuses all-bills run when sway_locale is omitted" do
      service = described_class.new(stages: ["fetch-bills"])
      expect { service.call }
        .to raise_error(LegislationPipelineRunService::MissingLocaleError, /A SwayLocale is required for all-bills pipeline runs/)
    end

    it "refuses single-bill run when passed sway_locale conflicts with bill jurisdiction" do
      bill = create(:bill, sway_locale: sway_locale)
      other_locale = create(:sway_locale, :maryland)
      expect {
        described_class.new(stages: ["fetch-bills"], bill: bill, sway_locale: other_locale)
      }.to raise_error(LegislationPipelineRunService::LocaleMismatchError, /Single-bill pipeline run cannot override bill jurisdiction with a conflicting locale/)
    end

    it "derives sway_locale from bill for single-bill runs" do
      bill = create(:bill, sway_locale: sway_locale)
      service = described_class.new(stages: ["fetch-bills"], bill: bill)
      expect { service.call }.to change(LegislationPipelineRun, :count).by(1)
      expect(LegislationPipelineRun.last&.sway_locale_id).to eq(sway_locale.id)
    end

    # summarize-bill is no longer blocked from the allowed-stage list. Operators
    # can now pick it like any other stage.
    it "accepts summarize-bill in stages allowlist" do
      service = described_class.new(stages: ["fetch-bills", "summarize-bill"], sway_locale: sway_locale)
      expect { service.call }.not_to raise_error
    end

    it "still rejects unknown / typo stages with a useful message" do
      service = described_class.new(stages: ["bogus-stage"], sway_locale: sway_locale)
      expect { service.call }.to raise_error(LegislationPipelineRunService::StageAllowlistError, /Unknown stages.*bogus-stage/)
    end

    it "accepts a bill association for per-bill refresh" do
      bill = create(:bill)
      service = described_class.new(bill: bill, stages: described_class::ALLOWED_PIPELINE_STAGES)
      expect { service.call }.to change(LegislationPipelineRun, :count).by(1)
      last_run = LegislationPipelineRun.last #: LegislationPipelineRun
      expect(last_run.bill_id).to eq(bill.id)
      expect(last_run.sway_locale_id).to eq(bill.sway_locale_id)
    end

    # The only keyword here is `download_missing_assets:` — the old
    # `refresh:` is gone with no shim. The refresh COLUMN stays in the
    # database, but nothing reads it.
    it "defaults download_missing_assets to true and persists it on the run row" do
      service = described_class.new(stages: ["fetch-bills"], sway_locale: sway_locale)
      service.call
      expect(LegislationPipelineRun.last&.download_missing_assets).to eq(true)
    end

    it "persists download_missing_assets: false when explicitly requested" do
      service = described_class.new(stages: ["fetch-bills"], sway_locale: sway_locale, download_missing_assets: false)
      service.call
      expect(LegislationPipelineRun.last&.download_missing_assets).to eq(false)
    end

    it "does not accept a refresh: kwarg (direct replacement)" do
      expect {
        described_class.new(stages: ["fetch-bills"], sway_locale: sway_locale, refresh: false)
      }.to raise_error(ArgumentError, /unknown keyword: :refresh/)
    end
  end

  # `.concurrency_blocked?` was removed with the method. The check stopping
  # two runs at once is now inline in BillsController#run_pipeline, pinned
  # by two request specs.

  # .reconcile_from_remote_conflict! was removed with the service
  # method — it handled 409s from the separate pipeline service, which no
  # longer exists.

  # What #resume and #restart promise. These examples were written and left
  # pending before #resume, #restart and ResumeNotAllowed existed, then switched
  # on once those were implemented.
  describe "#resume" do
    let(:scoped_bill) { create(:bill, external_id: "B-100") }
    let(:failed_run) {
      create(:legislation_pipeline_run, :failed, bill: scoped_bill, stages: %w[fetch-bills extract-text])
    }

    it "creates a new run with origin='resume' and parent_run_id pointing to failed_run.id" do
      new_run = described_class.new.resume(failed_run)
      expect(new_run.origin).to eq("resume")
      expect(new_run.parent_run_id).to eq(failed_run.id.to_s)
      expect(new_run.bill_id).to eq(failed_run.bill_id)
    end

    it "preserves sway_locale from parent run on resume" do
      failed_run.update!(sway_locale: sway_locale)
      new_run = described_class.new.resume(failed_run)
      expect(new_run.sway_locale_id).to eq(sway_locale.id)
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    it "tells the job it is a resume, not just the row" do
      allow(RunLegislationPipelineJob).to receive(:perform_later)

      new_run = described_class.new.resume(failed_run)

      expect(RunLegislationPipelineJob).to have_received(:perform_later).with(new_run.id, origin: "resume")
    end

    # Pins which id goes into the foreign key, guarding against the old
    # `remote_run_id` UUID column creeping back — a system spec once looked
    # it up and got nil.
    it "writes parent_run_id as parent.id.to_s (NOT parent.remote_run_id)" do
      failed_run.update!(remote_run_id: "uuid-XYZ-from-pre-phase-52-sidecar-era")
      new_run = described_class.new.resume(failed_run)
      expect(new_run.parent_run_id).to eq(failed_run.id.to_s)
      expect(new_run.parent_run_id).not_to eq("uuid-XYZ-from-pre-phase-52-sidecar-era")
    end

    it "preserves stages and download_missing_assets from parent run on the new resume row (verbatim inheritance)" do
      new_run = described_class.new.resume(failed_run)
      expect(new_run.stages).to eq(failed_run.stages)
      expect(new_run.download_missing_assets).to eq(failed_run.download_missing_assets)
    end

    it "inherits download_missing_assets=false verbatim from a parent whose dma is false" do
      failed_run.update!(download_missing_assets: false)
      new_run = described_class.new.resume(failed_run)
      expect(new_run.download_missing_assets).to be(false)
    end

    it "enqueues RunLegislationPipelineJob for the new run" do
      expect { described_class.new.resume(failed_run) }
        .to have_enqueued_job(RunLegislationPipelineJob)
    end

    it "raises ResumeNotAllowed when parent.status != 'failed' (server-side guard, REVIEWS.md HIGH)" do
      succeeded_run = create(:legislation_pipeline_run, status: "succeeded", bill: create(:bill, external_id: "B-100"))
      expect { described_class.new.resume(succeeded_run) }.to raise_error(LegislationPipelineRunService::ResumeNotAllowed)
    end

    it "raises ResumeNotAllowed when parent.kind != 'single' (resume only valid for single-bill runs)" do
      all_bills_run = create(:legislation_pipeline_run, :failed)
      expect { described_class.new.resume(all_bills_run) }.to raise_error(LegislationPipelineRunService::ResumeNotAllowed)
    end

    # Stopping two runs at once is the CONTROLLER's job, not the service's —
    # inline in BillsController#resume/restart_pipeline_run; the standalone
    # `.concurrency_blocked?` was removed.
    it "ignores concurrency state at the service layer (controller owns the gate)" do
      failed_run # referenced first so it exists before the active run is seeded
      seed_active_pipeline_run(status: "running")
      starting_count = LegislationPipelineRun.count
      described_class.new.resume(failed_run)
      expect(LegislationPipelineRun.count).to eq(starting_count + 1)
      expect(LegislationPipelineRun.last!.origin).to eq("resume")
    end
  end

  describe "#restart" do
    let(:scoped_bill) { create(:bill, external_id: "B-100") }
    let(:failed_run) {
      create(:legislation_pipeline_run, :failed, bill: scoped_bill, stages: %w[fetch-bills extract-text])
    }

    it "creates a new run with origin='restart' and parent_run_id pointing to failed_run.id" do
      new_run = described_class.new.restart(failed_run, download_missing_assets: false)
      expect(new_run.origin).to eq("restart")
      expect(new_run.parent_run_id).to eq(failed_run.id.to_s)
    end

    it "preserves sway_locale from parent run on restart" do
      failed_run.update!(sway_locale: sway_locale)
      new_run = described_class.new.restart(failed_run)
      expect(new_run.sway_locale_id).to eq(sway_locale.id)
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#Restart rejects indeterminate runs without a locale]]
    it "raises MissingLocaleError on restart when legacy all-bills parent lacks sway_locale" do
      legacy_all_bills_run = create(
        :legislation_pipeline_run,
        :failed,
        bill: nil,
        sway_locale: nil,
        stages: %w[fetch-bills extract-text]
      )

      expect {
        described_class.new.restart(legacy_all_bills_run)
      }.to raise_error(
        LegislationPipelineRunService::MissingLocaleError,
        "A SwayLocale is required for all-bills pipeline runs"
      )
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#Restart rejects indeterminate runs without a locale]]
    it "resolves bill.sway_locale on restart when legacy single-bill parent lacks sway_locale" do
      scoped_bill.update!(sway_locale: sway_locale)
      legacy_single_bill_run = create(
        :legislation_pipeline_run,
        :failed,
        bill: scoped_bill,
        sway_locale: nil,
        stages: %w[fetch-bills extract-text]
      )

      new_run = described_class.new.restart(legacy_single_bill_run)
      expect(new_run.sway_locale_id).to eq(sway_locale.id)
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    it "tells the job it is a restart, not just the row" do
      allow(RunLegislationPipelineJob).to receive(:perform_later)

      new_run = described_class.new.restart(failed_run, download_missing_assets: false)

      expect(RunLegislationPipelineJob).to have_received(:perform_later).with(new_run.id, origin: "restart")
    end

    it "preserves bill scoping and stages from parent on the new restart row (full re-attempt from stage 1)" do
      new_run = described_class.new.restart(failed_run, download_missing_assets: false)
      expect(new_run.bill_id).to eq(failed_run.bill_id)
      expect(new_run.stages).to eq(failed_run.stages)
    end

    # restart takes download_missing_assets from the parent run by default; the
    # operator can override it with a keyword argument.
    it "defaults download_missing_assets to parent_run.download_missing_assets when no kwarg supplied" do
      failed_run.update!(download_missing_assets: false)
      new_run = described_class.new.restart(failed_run)
      expect(new_run.download_missing_assets).to be(false)
    end

    it "defaults download_missing_assets=true when parent dma is true and no kwarg supplied" do
      failed_run.update!(download_missing_assets: true)
      new_run = described_class.new.restart(failed_run)
      expect(new_run.download_missing_assets).to be(true)
    end

    it "accepts an explicit download_missing_assets: override that flips parent dma to true" do
      failed_run.update!(download_missing_assets: false)
      new_run = described_class.new.restart(failed_run, download_missing_assets: true)
      expect(new_run.download_missing_assets).to be(true)
    end

    it "accepts an explicit download_missing_assets: override that flips parent dma to false" do
      failed_run.update!(download_missing_assets: true)
      new_run = described_class.new.restart(failed_run, download_missing_assets: false)
      expect(new_run.download_missing_assets).to be(false)
    end

    it "does not accept a refresh: kwarg (direct replacement)" do
      expect {
        described_class.new.restart(failed_run, refresh: false)
      }.to raise_error(ArgumentError, /unknown keyword: :refresh/)
    end

    it "enqueues RunLegislationPipelineJob for the new run" do
      expect { described_class.new.restart(failed_run, download_missing_assets: false) }
        .to have_enqueued_job(RunLegislationPipelineJob)
    end

    # Same as #resume: stopping two runs at once happens in the controller, not
    # in the service. See the note on #resume above.
    it "ignores concurrency state at the service layer (controller owns the gate)" do
      failed_run # referenced first so it exists before the active run is seeded
      seed_active_pipeline_run(status: "running")
      starting_count = LegislationPipelineRun.count
      described_class.new.restart(failed_run, download_missing_assets: false)
      expect(LegislationPipelineRun.count).to eq(starting_count + 1)
      expect(LegislationPipelineRun.last!.origin).to eq("restart")
    end
  end
end
