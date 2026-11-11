# frozen_string_literal: true

require "rails_helper"

RSpec.describe RunLegislationPipelineJob do
  let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
  let(:run) { create(:legislation_pipeline_run) }

  before do
    allow(PipelineRunChannel).to receive(:broadcast_to)
  end

  def with_tmp_legislation_roots(prefix)
    raw_root = Dir.mktmpdir("#{prefix}-raw")
    text_root = Dir.mktmpdir("#{prefix}-text")
    begin
      with_app_config(:legislation, legislation_bills_raw_root: raw_root, legislation_bills_text_root: text_root) do
        yield raw_root, text_root
      end
    ensure
      FileUtils.rm_rf(raw_root)
      FileUtils.rm_rf(text_root)
    end
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why resolve_bill passes no locale]]
  describe "#resolve_bill (A1-WR-03)" do
    subject(:job) { described_class.new }

    it "resolves the bill when exactly one carries the external_id" do
      bill = create(:bill, external_id: "RB-001", scheduled_release_date_utc: 300.days.ago)
      bill_run = create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "RB-001")

      expect(job.send(:resolve_bill, bill_run)).to eq(bill)
    end

    # The test that had to fail first, before the fix existed.
    it "returns nil rather than an arbitrary row when two locales share the external_id and run has no matching locale" do
      create(:bill, external_id: "RB-DUP", scheduled_release_date_utc: 301.days.ago)
      create(:bill, external_id: "RB-DUP", sway_locale: create(:sway_locale), scheduled_release_date_utc: 302.days.ago)
      unmatched_run = create(:legislation_pipeline_run, sway_locale: nil)
      bill_run = create(:pipeline_run_bill, legislation_pipeline_run: unmatched_run, bill_external_id: "RB-DUP")

      expect(job.send(:resolve_bill, bill_run)).to be_nil
    end

    it "resolves to the run's locale bill when two locales share an external_id" do
      baltimore_loc = create(:sway_locale, :baltimore)
      maryland_loc = create(:sway_locale, :maryland)
      baltimore_bill = create(:bill, external_id: "SHARED-02", sway_locale: baltimore_loc, scheduled_release_date_utc: 305.days.ago)
      maryland_bill = create(:bill, external_id: "SHARED-02", sway_locale: maryland_loc, scheduled_release_date_utc: 306.days.ago)

      baltimore_run = create(:legislation_pipeline_run, bill: nil, sway_locale: baltimore_loc)
      maryland_run = create(:legislation_pipeline_run, bill: nil, sway_locale: maryland_loc)

      prb_baltimore = create(:pipeline_run_bill, legislation_pipeline_run: baltimore_run, bill_external_id: "SHARED-02")
      prb_maryland = create(:pipeline_run_bill, legislation_pipeline_run: maryland_run, bill_external_id: "SHARED-02")

      expect(job.send(:resolve_bill, prb_baltimore)).to eq(baltimore_bill)
      expect(job.send(:resolve_bill, prb_maryland)).to eq(maryland_bill)
    end
  end

  # @lat: [[legislation-pipeline#Artifacts are files, not rows]]
  describe "#hydrate_pipeline_run_bills_from_disk!" do
    subject(:job) { described_class.new }

    let(:no_fetch_run) do
      create(:legislation_pipeline_run, bill: nil, stages: ["extract-text", "parse-sections"])
    end

    it "hydrates from disk for an all-bills run with no fetch-bills and no rows" do
      seeder = instance_double(FetchBillsService, seed_from_disk: 3)
      allow(FetchBillsService).to receive(:new).with(run: no_fetch_run).and_return(seeder)

      job.send(:hydrate_pipeline_run_bills_from_disk!, no_fetch_run)

      expect(seeder).to have_received(:seed_from_disk)
    end

    it "no-ops when fetch-bills is operator-checked (discover will seed)" do
      discover_run = create(:legislation_pipeline_run, bill: nil, stages: ["fetch-bills", "extract-text"])
      allow(FetchBillsService).to receive(:new)

      job.send(:hydrate_pipeline_run_bills_from_disk!, discover_run)

      expect(FetchBillsService).not_to have_received(:new)
    end

    it "no-ops for a single-bill run (handled by the pre-seed)" do
      bill = create(:bill, external_id: "CCB-25-0009", sway_locale: sway_locale)
      single_run = create(:legislation_pipeline_run, bill: bill, stages: ["extract-text"])
      allow(FetchBillsService).to receive(:new)

      job.send(:hydrate_pipeline_run_bills_from_disk!, single_run)

      expect(FetchBillsService).not_to have_received(:new)
    end

    it "no-ops when the run already has pipeline_run_bills rows" do
      PipelineRunBill.create!(legislation_pipeline_run: no_fetch_run,
        bill_external_id: "CCB-25-0001", status: "pending", sort_order: 0)
      allow(FetchBillsService).to receive(:new)

      job.send(:hydrate_pipeline_run_bills_from_disk!, no_fetch_run)

      expect(FetchBillsService).not_to have_received(:new)
    end

    it "scopes hydration of existing bills to the run's SwayLocale" do
      baltimore_loc = create(:sway_locale, :baltimore)
      maryland_loc = create(:sway_locale, :maryland)

      create(:bill, external_id: "BALT-ALL-1", sway_locale: baltimore_loc, scheduled_release_date_utc: 310.days.ago)
      create(:bill, external_id: "MD-ALL-1", sway_locale: maryland_loc, scheduled_release_date_utc: 311.days.ago)

      md_run = create(:legislation_pipeline_run, bill: nil, sway_locale: maryland_loc, stages: ["extract-text"])

      seeder = instance_double(FetchBillsService, seed_from_disk: 0)
      allow(FetchBillsService).to receive(:new).with(run: md_run).and_return(seeder)

      job.send(:hydrate_pipeline_run_bills_from_disk!, md_run)

      hydrated_ids = md_run.pipeline_run_bills.pluck(:bill_external_id)
      expect(hydrated_ids).to contain_exactly("MD-ALL-1")
      expect(hydrated_ids).not_to include("BALT-ALL-1")
    end

    it "unions disk-hydrated bills with database-only bills for the run locale without duplicates" do
      maryland_loc = create(:sway_locale, :maryland)
      baltimore_loc = create(:sway_locale, :baltimore)

      create(:bill, external_id: "MD-DISK-1", sway_locale: maryland_loc, scheduled_release_date_utc: 300.days.ago)
      create(:bill, external_id: "MD-DB-ONLY", sway_locale: maryland_loc, scheduled_release_date_utc: 301.days.ago)
      create(:bill, external_id: "BALT-DB-ONLY", sway_locale: baltimore_loc, scheduled_release_date_utc: 302.days.ago)

      md_run = create(:legislation_pipeline_run, bill: nil, sway_locale: maryland_loc, stages: ["extract-text"])

      seeder = instance_double(FetchBillsService)
      allow(seeder).to receive(:seed_from_disk) do
        PipelineRunBill.create!(
          legislation_pipeline_run: md_run,
          bill_external_id: "MD-DISK-1",
          status: "pending",
          sort_order: 0
        )
        1
      end
      allow(FetchBillsService).to receive(:new).with(run: md_run).and_return(seeder)

      job.send(:hydrate_pipeline_run_bills_from_disk!, md_run)

      hydrated_ids = md_run.pipeline_run_bills.reload.pluck(:bill_external_id)
      expect(hydrated_ids).to contain_exactly("MD-DISK-1", "MD-DB-ONLY")
      expect(hydrated_ids).not_to include("BALT-DB-ONLY")
      expect(md_run.pipeline_run_bills.order(:sort_order).pluck(:sort_order)).to eq([0, 1])
    end
  end

  describe "ORIGIN_VALUES allowlist (CR-02)" do
    it "defines ORIGIN_VALUES with fresh, resume, restart, seed" do
      expect(described_class::ORIGIN_VALUES).to match_array(%w[fresh resume restart seed])
    end

    it "logs a structured warning when an unknown origin is supplied" do
      run = create(:legislation_pipeline_run)
      expect(SwayLogging).to receive(:warn).with(
        "run_legislation_pipeline.unknown_origin",
        hash_including(run_id: run.id, origin: "bogus-origin")
      )
      # The job carries on afterwards. What happens next does not matter here,
      # only that the warning fired before normal work continued.
      allow(SwayLogging).to receive(:info)
      allow(SwayLogging).to receive(:error)
      # No bills were seeded, so a later guard trips and the run fails. That is
      # fine — the expectation above is on the warning, which already happened.
      expect {
        described_class.new.perform(run.id, origin: "bogus-origin")
      }.to raise_error(StandardError)
    end

    it "does NOT log unknown_origin for any of the documented values" do
      run = create(:legislation_pipeline_run)
      expect(SwayLogging).not_to receive(:warn).with("run_legislation_pipeline.unknown_origin", anything)
      allow(SwayLogging).to receive(:info)
      allow(SwayLogging).to receive(:warn) # other warns are fine
      allow(SwayLogging).to receive(:error)
      expect {
        described_class.new.perform(run.id, origin: "seed")
      }.to raise_error(StandardError)
    end
  end

  describe "DAG_ORDER (regression-prevention)" do
    it "matches the verbatim order — fetch_law BEFORE extract_text" do
      expect(described_class::DAG_ORDER).to eq(
        [:fetch_bills, :fetch_law, :extract_text, :parse_sections,
          :generate_diffs, :fetch_hearings, :clean_testimony, :summarize]
      )
      expect(described_class::DAG_ORDER.index(:fetch_law)).to eq(1)
      expect(described_class::DAG_ORDER.index(:fetch_law))
        .to be < described_class::DAG_ORDER.index(:extract_text)
    end

    it "classifies fetch_bills + fetch_law as RUN_LEVEL_STAGES" do
      expect(described_class::RUN_LEVEL_STAGES).to eq([:fetch_bills, :fetch_law])
    end

    it "classifies the other six as BILL_LEVEL_STAGES" do
      expect(described_class::BILL_LEVEL_STAGES).to eq(
        [:extract_text, :parse_sections, :generate_diffs, :fetch_hearings, :clean_testimony, :summarize]
      )
    end

    it "STAGE_SERVICES wires every DAG stage (inline-call stages map to nil)" do
      expect(described_class::STAGE_SERVICES.keys).to match_array(described_class::DAG_ORDER)
      expect(described_class::STAGE_SERVICES[:fetch_law]).to eq("FetchLawService")
      expect(described_class::STAGE_SERVICES[:extract_text]).to be_nil
      expect(described_class::STAGE_SERVICES[:summarize]).to be_nil
    end

    it "CONSECUTIVE_FAILURE_BUDGET is 5" do
      expect(described_class::CONSECUTIVE_FAILURE_BUDGET).to eq(5)
    end
  end

  describe "state-machine durability (no migration added)" do
    it "exposes the expected start_/complete_/can_start_ predicates for fetch_law" do
      methods = LegislationPipelineRun.instance_methods
      expect(methods).to include(
        :start_fetch_law!,
        :complete_fetch_law!,
        :can_start_fetch_law?,
        :can_complete_fetch_law?,
        :fetching_law?
      )
    end

    it "ALLOWED_PIPELINE_STAGES includes 'fetch-law'" do
      expect(LegislationPipelineRun::ALLOWED_PIPELINE_STAGES).to include("fetch-law")
    end

    # An operator can pick summarize-bill on its own, so the list of allowed
    # stage names has to contain it.
    it "ALLOWED_PIPELINE_STAGES includes 'summarize-bill'" do
      expect(LegislationPipelineRun::ALLOWED_PIPELINE_STAGES).to include("summarize-bill")
    end

    it "PHASE_52_STAGE_STATES has :fetching_law second" do
      expect(LegislationPipelineRun::PHASE_52_STAGE_STATES.first(2))
        .to eq([:fetching_bills, :fetching_law])
    end
  end

  describe "#perform — RUN_LEVEL stage dispatch" do
    it "invokes FetchBillsService and FetchLawService with the run kwarg" do
      stub_bills = instance_double(FetchBillsService, call: [])
      stub_law = instance_double(FetchLawService, call: {"sections_upserted" => 0})
      # When the operator ticked fetch-bills themselves, FetchBillsService is
      # built with `mode: :discover`. That applies here, because the factory
      # fills stages with every allowed stage, fetch-bills included.
      allow(FetchBillsService).to receive(:new).with(run: run, mode: :discover).and_return(stub_bills)
      allow(FetchLawService).to receive(:new).with(run: run).and_return(stub_law)

      # The run has no PipelineRunBill rows, so no per-bill stage can run. The
      # first per-bill stage then trips the "nothing succeeded in this stage"
      # guard, which raises StageError and fails the run.
      expect { described_class.new.perform(run.id) }.to raise_error(StageError)
      expect(stub_bills).to have_received(:call)
      expect(stub_law).to have_received(:call)
    end

    it "carries on when a run-level stage raises a per-row BillProcessingError, leaving run non-failed and executing later stages" do
      run_two_stages = create(:legislation_pipeline_run, stages: %w[fetch-bills fetch-law])
      stub_bills = instance_double(FetchBillsService)
      stub_law = instance_double(FetchLawService, call: {"sections_upserted" => 0})

      allow(FetchBillsService).to receive(:new).with(run: run_two_stages, mode: :discover).and_return(stub_bills)
      allow(stub_bills).to receive(:call).and_raise(BillProcessingError, "malformed date on single row")
      allow(FetchLawService).to receive(:new).with(run: run_two_stages).and_return(stub_law)
      allow(SwayLogging).to receive(:warn)

      expect { described_class.new.perform(run_two_stages.id) }.not_to raise_error

      expect(run_two_stages.reload.status).not_to eq("failed")
      expect(stub_law).to have_received(:call)
    end

    it "fails the run, marks fetch_bills stage failed, and re-raises StageError when FetchBillsService raises BillProcessingError for missing active session" do
      run_two_stages = create(:legislation_pipeline_run, stages: %w[fetch-bills fetch-law])
      stub_bills = instance_double(FetchBillsService)
      stub_law = instance_double(FetchLawService, call: {"sections_upserted" => 0})

      allow(FetchBillsService).to receive(:new).with(run: run_two_stages, mode: :discover).and_return(stub_bills)
      allow(stub_bills).to receive(:call).and_raise(
        BillProcessingError, "No active session found for HTML legislation discovery"
      )
      allow(FetchLawService).to receive(:new).with(run: run_two_stages).and_return(stub_law)

      expect {
        described_class.new.perform(run_two_stages.id)
      }.to raise_error(StageError, "No active session found for HTML legislation discovery")

      expect(run_two_stages.reload.status).to eq("failed")
      expect(run_two_stages.current_stage).to eq("fetch_bills")
      expect(stub_law).not_to have_received(:call)

      stage_record = run_two_stages.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      expect(stage_record&.status).to eq("failed")
      expect(stage_record&.status).not_to eq("succeeded")
    end

    it "fails the run, marks fetch_bills stage failed, and re-raises StageError when FetchBillsService raises BillProcessingError with fetch_bills adapter prefix" do
      run_two_stages = create(:legislation_pipeline_run, stages: %w[fetch-bills fetch-law])
      stub_bills = instance_double(FetchBillsService)
      stub_law = instance_double(FetchLawService, call: {"sections_upserted" => 0})

      allow(FetchBillsService).to receive(:new).with(run: run_two_stages, mode: :discover).and_return(stub_bills)
      allow(stub_bills).to receive(:call).and_raise(
        BillProcessingError, "fetch_bills: network error: connection reset by peer"
      )
      allow(FetchLawService).to receive(:new).with(run: run_two_stages).and_return(stub_law)

      expect {
        described_class.new.perform(run_two_stages.id)
      }.to raise_error(StageError, "fetch_bills: network error: connection reset by peer")

      expect(run_two_stages.reload.status).to eq("failed")
      expect(run_two_stages.current_stage).to eq("fetch_bills")
      expect(stub_law).not_to have_received(:call)

      stage_record = run_two_stages.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      expect(stage_record&.status).to eq("failed")
      expect(stage_record&.status).not_to eq("succeeded")
    end

    it "fails the run, marks fetch_law stage failed, and re-raises StageError when FetchLawService raises BillProcessingError with fetch_law prefix" do
      run_two_stages = create(:legislation_pipeline_run, stages: %w[fetch-bills fetch-law])
      stub_bills = instance_double(FetchBillsService, call: [])
      stub_law = instance_double(FetchLawService)

      allow(FetchBillsService).to receive(:new).with(run: run_two_stages, mode: :discover).and_return(stub_bills)
      allow(FetchLawService).to receive(:new).with(run: run_two_stages).and_return(stub_law)
      allow(stub_law).to receive(:call).and_raise(
        BillProcessingError, "fetch_law: corpus extraction failed: corrupt zip archive"
      )

      expect {
        described_class.new.perform(run_two_stages.id)
      }.to raise_error(StageError, "fetch_law: corpus extraction failed: corrupt zip archive")

      expect(run_two_stages.reload.status).to eq("failed")
      expect(run_two_stages.current_stage).to eq("fetch_law")

      fetch_bills_stage = run_two_stages.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      expect(fetch_bills_stage&.status).to eq("succeeded")

      fetch_law_stage = run_two_stages.pipeline_run_stages.find_by(stage_name: "fetch_law")
      expect(fetch_law_stage&.status).to eq("failed")
      expect(fetch_law_stage&.status).not_to eq("succeeded")
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
    it "fails the run when a run-level stage raises EmptyStageError and marks the stage failed so resume retries it" do
      run_two_stages = create(:legislation_pipeline_run, stages: %w[fetch-bills fetch-law])
      stub_bills = instance_double(FetchBillsService)
      stub_law = instance_double(FetchLawService, call: {"sections_upserted" => 0})

      allow(FetchBillsService).to receive(:new).with(run: run_two_stages, mode: :discover).and_return(stub_bills)
      allow(stub_bills).to receive(:call).and_raise(EmptyStageError, "fetch_bills: no bills were discovered")
      allow(FetchLawService).to receive(:new).with(run: run_two_stages).and_return(stub_law)

      expect {
        described_class.new.perform(run_two_stages.id)
      }.to raise_error(StageError)

      expect(run_two_stages.reload.status).to eq("failed")
      expect(stub_law).not_to have_received(:call)

      stage_record = run_two_stages.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      expect(stage_record&.status).to eq("failed")
      expect(stage_record&.status).not_to eq("succeeded")

      resume_run = create(:legislation_pipeline_run, origin: "resume", parent_run: run_two_stages, stages: %w[fetch-bills fetch-law])
      remaining = described_class.new.send(:stages_to_run, resume_run, "resume")
      expect(remaining).to include(:fetch_bills)
    end
  end

  describe "#perform — BILL_LEVEL stage dispatch + stage_results JSON" do
    let(:bill) { create(:bill, external_id: "TEST-BILL-1", sway_locale: sway_locale) }
    let!(:bill_run) do
      create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id,
        stage_results: {})
    end

    before do
      # Fake the run-level services so the job can move on to the per-bill stages.
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      # Mark the per-bill stages already succeeded so the job skips extract_text
      # and moves on.
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      bill_run.update_columns(stage_results: {
        "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "parse_sections" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "generate_diffs" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "clean_testimony" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "summarize" => {"status" => "succeeded", "at" => Time.current.iso8601}
      })
    end

    it "treats every stage with a prior succeeded entry as a no-op (resume-ish semantics)" do
      described_class.new.perform(run.id)

      bill_run.reload
      %w[extract_text parse_sections generate_diffs fetch_hearings clean_testimony summarize].each do |stage|
        expect(bill_run.stage_results.dig(stage, "status")).to eq("succeeded")
      end
    end
  end

  # @lat: [[pipeline-stage-results-json-set#Why the key set is checked against the real method, not a hand-typed fixture]]
  describe "#record_stage_result — the key set ResourceCachePanelSerializer reads" do
    let!(:bill_run) do
      create(:pipeline_run_bill, legislation_pipeline_run: run, stage_results: {})
    end

    it "writes status and at, and never finished_at" do
      described_class.new.send(:record_stage_result, bill_run, :extract_text, "succeeded")

      entry = bill_run.reload.stage_results.fetch("extract_text")
      expect(entry.keys).to match_array(%w[status at])
    end

    it "adds error and reason only when the caller passes them" do
      described_class.new.send(
        :record_stage_result, bill_run, :extract_text, "failed",
        error: "boom", reason: "why"
      )

      entry = bill_run.reload.stage_results.fetch("extract_text")
      expect(entry.keys).to match_array(%w[status at error reason])
    end
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why the operator-abort path logs and exits cleanly instead of calling handle_run_failure]]
  describe "#perform — operator Force-Fail abort during bill-level stage" do
    let(:bill_one) { create(:bill, external_id: "OP-ABORT-1", sway_locale: sway_locale, scheduled_release_date_utc: 90.days.ago) }
    let(:bill_two) { create(:bill, external_id: "OP-ABORT-2", sway_locale: sway_locale, scheduled_release_date_utc: 91.days.ago) }
    let!(:bill_run_one) do
      create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill_one.external_id,
        stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
    end
    let!(:bill_run_two) do
      create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill_two.external_id,
        stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
    end

    before do
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      # The first bill's parse_sections succeeds and, at the same moment,
      # pretends the operator hit Force Fail mid-stage by driving the run to
      # :failed through the state machine's force_fail! event.
      call_count = 0
      allow(ParseSectionsService).to receive(:new) do
        call_count += 1
        if call_count == 1
          run.reload.force_fail! if run.reload.can_force_fail?
        end
        instance_double(ParseSectionsService, call: nil)
      end
    end

    it "raises OperatorAbortError on the next bill iteration after operator force-fails the run" do
      # #perform catches OperatorAbortError and does not re-raise it. The run has
      # already ended, so there is no error to pass upward. Bill 2 must stop at
      # its re-read check.
      expect { described_class.new.perform(run.id) }.not_to raise_error
      expect(run.reload.status).to eq("failed")
      # The loop reached bill 2, but the re-read check raised before its state
      # change fired.
      expect(bill_run_two.reload.status).to eq("pending")
    end

    it "does not call handle_run_failure when the run is already terminal" do
      # If handle_run_failure ran, it would call run.force_fail! on a run that is
      # already :failed and raise StateMachines::InvalidTransition. No raise plus
      # no extra audit entries together show the rescue branch exited cleanly.
      entries_before = PipelineActivityLogEntry.count
      described_class.new.perform(run.id)
      entries_after = PipelineActivityLogEntry.count
      # The only entries should be the ones the controller's force_fail wrote.
      # The job must not add a second, duplicate "force-fail → failed" entry.
      added_entries = PipelineActivityLogEntry.order(id: :desc).limit(entries_after - entries_before)
      forced_count = added_entries.count { |e| e.payload["event"] == "force_fail" }
      expect(forced_count).to be <= 1
    end
  end

  describe "#perform — bill-level failures + stage_results recording" do
    let(:bill) { create(:bill, external_id: "TEST-BILL-FAIL", sway_locale: sway_locale) }
    let!(:bill_run) do
      create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id,
        stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
    end

    before do
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      allow(ParseSectionsService).to receive(:new).and_raise(BillProcessingError, "boom")
    end

    it "marks the bill failed, records stage_results entry, and raises StageError when only bill fails" do
      expect { described_class.new.perform(run.id) }.to raise_error(StageError, /all bills failed in stage parse_sections/)
      bill_run.reload
      expect(bill_run.stage_results.dig("parse_sections", "status")).to eq("failed")
      expect(bill_run.stage_results.dig("parse_sections", "error")).to include("boom")
    end

    it "records the truncated error message on the pipeline_run_bill row when a bill fails" do
      expect { described_class.new.perform(run.id) }.to raise_error(StageError, /all bills failed in stage parse_sections/)
      expect(bill_run.reload.error_message).to eq("boom")
    end

    it "records error message and stage results before re-raising StageError on unexpected runtime error" do
      allow(ParseSectionsService).to receive(:new).and_raise(RuntimeError, "unexpected crash")

      expect { described_class.new.perform(run.id) }
        .to raise_error(StageError, /stage parse_sections crashed on bill #TEST-BILL-FAIL: RuntimeError: unexpected crash/)

      bill_run.reload
      expect(bill_run.error_message).to eq("unexpected crash")
      expect(bill_run.stage_results.dig("parse_sections", "status")).to eq("failed")
      expect(bill_run.stage_results.dig("parse_sections", "error")).to eq("RuntimeError: unexpected crash")
    end

    # @lat: [[pipeline-activity-logger-overview#Why a run failure must write an error-severity entry, checked by severity]]
    it "writes an error-severity entry to the Activity Log for this run" do
      expect { described_class.new.perform(run.id) }.to raise_error(StageError)

      error_entries = PipelineActivityLogEntry.errors_only
        .for_subject("LegislationPipelineRun", run.id.to_s)
      expect(error_entries).not_to be_empty
      expect(error_entries.last&.payload&.dig("error_message"))
        .to include("all bills failed in stage parse_sections")
    end

    # @lat: [[pipeline-activity-logger-overview#Why the run still reaches "failed" when the Activity Log write itself raises]]
    it "still marks the run failed when the Activity Log write raises" do
      allow(PipelineActivityLogger).to receive(:log_stage_failed!)
        .and_raise(ActiveRecord::StatementInvalid, "database is locked")

      expect { described_class.new.perform(run.id) }.to raise_error(StageError)

      expect(run.reload.status).to eq("failed")
    end

    describe "#record_bill_stage_failure" do
      it "rescues ArgumentError and logs invalid stage with recovery label" do
        allow(SwayLogging).to receive(:log_exception)

        expect {
          described_class.new.send(
            :record_bill_stage_failure,
            bill_run,
            :invalid_stage,
            BillProcessingError.new("something went wrong"),
            recovery_label: "bill_processing_error"
          )
        }.not_to raise_error

        expect(SwayLogging).to have_received(:log_exception).with(
          "orchestrator.record_stage_result_invalid_stage",
          exception: an_instance_of(ArgumentError),
          stage: :invalid_stage,
          recovery: "bill_processing_error"
        )
      end

      it "truncates error message to 500 characters" do
        long_msg = "x" * 600
        described_class.new.send(
          :record_bill_stage_failure,
          bill_run,
          :parse_sections,
          BillProcessingError.new(long_msg),
          recovery_label: "bill_processing_error"
        )

        expect(bill_run.reload.error_message.length).to eq(500)
        expect(bill_run.error_message).to end_with("...")
      end
    end
  end

  # @lat: [[pipeline-run-partial-vs-succeeded#Guaranteeing a terminal state]]
  describe "#perform — terminal status: succeeded vs partial (R18)" do
    # The two release dates differ because the database forbids two bills in the
    # same locale from sharing a scheduled_release_date_utc.
    let(:bill_ok) do
      create(:bill, external_id: "R18-OK", sway_locale: sway_locale,
        scheduled_release_date_utc: 80.days.ago)
    end
    let(:bill_fail) do
      create(:bill, external_id: "R18-FAIL", sway_locale: sway_locale,
        scheduled_release_date_utc: 81.days.ago)
    end

    # Mark the first four per-bill stages as already done, so only `summarize`
    # really runs. That isolates each bill's summarize result.
    def seed_through_hearings
      {
        "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "parse_sections" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "generate_diffs" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601}
      }
    end

    before do
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
    end

    it "lands in :succeeded when every bill succeeds" do
      create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 0,
        bill_external_id: bill_ok.external_id, stage_results: seed_through_hearings)
      allow(GenerateBillSummaryJob).to receive(:perform_now)

      described_class.new.perform(run.id)

      expect(run.reload.status).to eq("succeeded")
    end

    # @lat: [[pipeline-bill-stage-status-model#not_run: nothing was produced, but nothing failed]]
    it "does not record a bill as summarized when the summary job produced nothing" do
      prb = create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 0,
        bill_external_id: bill_ok.external_id, stage_results: seed_through_hearings)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
        .and_return(GenerateBillSummaryJob::NOT_RUN)

      described_class.new.perform(run.id)

      expect(prb.reload.stage_results.dig("summarize", "status")).to eq("not_run")
      expect(described_class.new.send(:stage_already_succeeded?, prb, :summarize)).to be(false)
      # No failure was recorded, so the run is not marked partial and the
      # failure budget is untouched.
      expect(run.reload.status).to eq("succeeded")
    end

    # @lat: [[pipeline-bill-stage-status-model#Why SETTLED must still count as done, checked through the resume gate itself]]
    it "still records :summarize as done when the job settled the row" do
      prb = create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 0,
        bill_external_id: bill_ok.external_id, stage_results: seed_through_hearings)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
        .and_return(GenerateBillSummaryJob::SETTLED)

      described_class.new.perform(run.id)

      expect(prb.reload.stage_results.dig("summarize", "status")).to eq("succeeded")
      expect(described_class.new.send(:stage_already_succeeded?, prb, :summarize)).to be(true)
    end

    it "records :summarize as skipped, not succeeded, when the job stood down without buying anything" do
      prb = create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 0,
        bill_external_id: bill_ok.external_id, stage_results: seed_through_hearings)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
        .and_return(GenerateBillSummaryJob::STOOD_DOWN)

      described_class.new.perform(run.id)

      prb.reload
      expect(prb.stage_results.dig("summarize", "status")).to eq("skipped")
      expect(prb.stage_results.dig("summarize", "reason")).to eq("no_model_call_made")
      expect(described_class.new.send(:stage_already_succeeded?, prb, :summarize)).to be(true)
    end

    # @lat: [[pipeline-bill-stage-status-model#not_run: nothing was produced, but nothing failed]]
    it "records no cause for a bill it cannot tell the cause for" do
      prb = create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 0,
        bill_external_id: bill_ok.external_id, stage_results: seed_through_hearings)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
        .and_return(GenerateBillSummaryJob::NOT_RUN)

      described_class.new.perform(run.id)

      reason = prb.reload.stage_results.dig("summarize", "reason")
      expect(reason).to eq("nothing_was_produced")
      expect(reason).not_to include("owns")
    end

    # @lat: [[pipeline-bill-stage-status-model#Reporting bills nothing ran for]]
    it "says so when a green run left bills with nothing produced" do
      create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 0,
        bill_external_id: bill_ok.external_id, stage_results: seed_through_hearings)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
        .and_return(GenerateBillSummaryJob::NOT_RUN)
      allow(SwayLogging).to receive(:warn)

      described_class.new.perform(run.id)

      expect(run.reload.status).to eq("succeeded")
      expect(SwayLogging).to have_received(:warn).with(
        "run_legislation_pipeline.bills_not_run", hash_including(not_run_bills: 1)
      )
    end

    it "stays quiet about it when every bill was summarized" do
      create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 0,
        bill_external_id: bill_ok.external_id, stage_results: seed_through_hearings)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
      allow(SwayLogging).to receive(:warn)

      described_class.new.perform(run.id)

      expect(SwayLogging).not_to have_received(:warn).with(
        "run_legislation_pipeline.bills_not_run", anything
      )
    end

    it "lands in :partial when a bill fails a stage even though its coarse status column still reads succeeded" do
      prb_ok = create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 0,
        bill_external_id: bill_ok.external_id, stage_results: seed_through_hearings)
      prb_fail = create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 1,
        bill_external_id: bill_fail.external_id, stage_results: seed_through_hearings)
      # @lat: [[pipeline-run-partial-vs-succeeded#Reading failure from stage_results, not the coarse status column]]
      [prb_ok, prb_fail].each { |prb| prb.update_column(:status, "succeeded") }

      allow(GenerateBillSummaryJob).to receive(:perform_now) do |bill_id|
        raise GenerateBillSummaryJob::BillSummaryError, "context overflow" if bill_id == bill_fail.id
      end

      described_class.new.perform(run.id)

      expect(run.reload.status).to eq("partial")
      # The failed bill's status column still says "succeeded". The failure is
      # recorded only in stage_results, which is where count_failed_bills looks.
      expect(prb_fail.reload.status).to eq("succeeded")
      expect(prb_fail.stage_results.dig("summarize", "status")).to eq("failed")
      expect(prb_ok.reload.stage_results.dig("summarize", "status")).to eq("succeeded")
    end
  end

  describe "#execute_bill_level_service — summarize per-bill failure isolation" do
    it "converts a GenerateBillSummaryJob::BillSummaryError into a per-bill BillProcessingError" do
      run = create(:legislation_pipeline_run)
      bill = create(:bill, external_id: "SUMMARIZE-FAIL-1")
      bill_run = create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
        .and_raise(GenerateBillSummaryJob::BillSummaryError, "llama.cpp response truncated")

      expect { described_class.new.send(:execute_bill_level_service, run, :summarize, bill_run) }
        .to raise_error(BillProcessingError, /summarize:.*truncated/)
    end
  end

  # @lat: [[pipeline-unsafe-external-id-rescue#This one rescue covers every reachable raise]]
  describe "#execute_bill_level_service — an unusable external_id is per-bill (A-WR-01)" do
    # @lat: [[legislation-path-segment-safety#Segment validation]]
    it "turns an unusable external_id into a per-bill BillProcessingError, refused at the bill lookup" do
      run = create(:legislation_pipeline_run)
      bill_run = create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: "../../../etc/passwd")

      expect { described_class.new.send(:execute_bill_level_service, run, :extract_text, bill_run) }
        .to raise_error(BillProcessingError, %r{no Bill row for external_id \.\./\.\./\.\./etc/passwd})
    end

    it "translates UnsafeExternalIdError from a stage service into a per-bill BillProcessingError" do
      run = create(:legislation_pipeline_run)
      bill = create(:bill, external_id: "UNSAFE-SEG-1")
      bill_run = create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id)
      allow(described_class::STAGE_SERVICES[:fetch_hearings].constantize).to receive(:new)
        .and_raise(Legislation::Paths::UnsafeExternalIdError, "not usable as a path segment")

      expect { described_class.new.send(:execute_bill_level_service, run, :fetch_hearings, bill_run) }
        .to raise_error(BillProcessingError, /fetch_hearings.*not usable as a path segment/m)
    end
  end

  # @lat: [[run-legislation-pipeline-job-internals#Inside execute_bill_level_service and execute_extract_text#Why a disk write failure converts to a per-bill failure]]
  describe "#execute_extract_text — a disk failure is per-bill (WR-E-01)" do
    it "turns a full disk into a per-bill BillProcessingError" do
      run = create(:legislation_pipeline_run)
      bill = create(:bill, external_id: "DISKFULL-1", extracted_text: nil)
      bill_run = create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id)
      allow(MupdfExtractor).to receive(:new).and_return(instance_double(MupdfExtractor, call: "Bill text."))
      allow(File).to receive(:write).and_raise(Errno::ENOSPC, "No space left on device")

      job = described_class.new
      allow(job).to receive(:locate_pdf).and_return(Pathname.new("/tmp/diskfull-1.pdf"))

      expect { job.send(:execute_bill_level_service, run, :extract_text, bill_run) }
        .to raise_error(BillProcessingError, /extract_text: artifact write failed.*ENOSPC/m)
    end

    # The text is on the row either way. The point of the conversion is that the
    # run carries on and comes back to this bill, not that the write is undone.
    it "keeps the extracted text it had already saved" do
      run = create(:legislation_pipeline_run)
      bill = create(:bill, external_id: "DISKFULL-2", extracted_text: nil)
      bill_run = create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id)
      allow(MupdfExtractor).to receive(:new).and_return(instance_double(MupdfExtractor, call: "Bill text."))
      allow(File).to receive(:write).and_raise(Errno::ENOSPC, "No space left on device")

      job = described_class.new
      allow(job).to receive(:locate_pdf).and_return(Pathname.new("/tmp/diskfull-2.pdf"))

      expect { job.send(:execute_bill_level_service, run, :extract_text, bill_run) }
        .to raise_error(BillProcessingError)
      expect(bill.reload.extracted_text).to eq("Bill text.")
    end

    it "writes the extracted text via a same-directory temp file renamed into place" do
      with_tmp_legislation_roots("wr-e-01") do |raw_root, _text_root|
        bill = create(:bill, external_id: "RENAME-EXTRACT-1", scheduled_release_date_utc: 310.days.ago)
        real_dir = File.join(raw_root, bill.sway_locale.name, "RENAME-EXTRACT-1")
        FileUtils.mkdir_p(real_dir)
        File.write(File.join(real_dir, "bill.pdf"), "%PDF-1.4")
        run = create(:legislation_pipeline_run)
        bill_run = create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: "RENAME-EXTRACT-1")
        allow(MupdfExtractor).to receive(:new).and_return(instance_double(MupdfExtractor, call: "extracted body text"))
        final_path = Legislation::Paths.bill_text_file("RENAME-EXTRACT-1", sway_locale: bill.sway_locale.name)
        seen_tmp_path = nil #: Pathname?
        expect(File).to receive(:rename).and_wrap_original do |original, from, to|
          tmp_path = Pathname(from)
          seen_tmp_path = tmp_path
          expect(to.to_s).to eq(final_path.to_s)
          expect(tmp_path.dirname).to eq(final_path.dirname)
          expect(tmp_path).not_to eq(final_path)
          original.call(from, to)
        end

        described_class.new.send(:execute_bill_level_service, run, :extract_text, bill_run)

        expect(seen_tmp_path).not_to be_nil
        expect(final_path.read).to eq("extracted body text")
        expect(final_path.dirname.children.map(&:to_s)).to eq([final_path.to_s])
      end
    end

    it "supplies usable text when extracted_text is already present on the bill record" do
      with_tmp_legislation_roots("wr-e-02") do |_raw_root, _text_root|
        bill = create(:bill, external_id: "PRESET-TEXT-1", extracted_text: "Pre-existing text from bill creator.")
        run = create(:legislation_pipeline_run, sway_locale: bill.sway_locale)
        bill_run = create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)

        job = described_class.new
        res = job.send(:execute_extract_text, bill_run)
        expect(res).to be_nil

        out_path = Legislation::Paths.bill_text_file(bill.external_id, sway_locale: bill.sway_locale.name)
        expect(File.exist?(out_path)).to be(true)
        expect(File.read(out_path)).to eq("Pre-existing text from bill creator.")
      end
    end

    it "supplies usable text when text artifact is already present on disk" do
      with_tmp_legislation_roots("wr-e-03") do |_raw_root, _text_root|
        bill = create(:bill, external_id: "DISK-TEXT-1", extracted_text: nil)
        run = create(:legislation_pipeline_run, sway_locale: bill.sway_locale)
        bill_run = create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)

        out_path = Legislation::Paths.bill_text_file(bill.external_id, sway_locale: bill.sway_locale.name)
        Legislation::ArtifactWriter.write(out_path, "Pre-existing text on disk.", stage: "extract_text")

        job = described_class.new
        res = job.send(:execute_extract_text, bill_run)
        expect(res).to be_nil
        expect(bill.reload.extracted_text).to eq("Pre-existing text on disk.")
      end
    end

    it "returns :skipped_no_pdf when neither PDF nor extracted text exists" do
      with_tmp_legislation_roots("wr-e-04") do |_raw_root, _text_root|
        bill = create(:bill, external_id: "NO-TEXT-1", extracted_text: nil)
        run = create(:legislation_pipeline_run, sway_locale: bill.sway_locale)
        bill_run = create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)

        job = described_class.new
        res = job.send(:execute_extract_text, bill_run)
        expect(res).to eq(:skipped_no_pdf)
      end
    end
  end

  # @lat: [[pipeline-bill-stage-status-model#The summarize dispatch path]]
  describe "#execute_bill_level_service — a stage that did no work must not report success (A-WR-04)" do
    it "refuses :summarize when no Bill row resolves" do
      run = create(:legislation_pipeline_run)
      bill_run = create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: "GHOST-SUMMARIZE-1")
      allow(GenerateBillSummaryJob).to receive(:perform_now)

      expect { described_class.new.send(:execute_bill_level_service, run, :summarize, bill_run) }
        .to raise_error(BillProcessingError, /no Bill row for external_id GHOST-SUMMARIZE-1/)
      expect(GenerateBillSummaryJob).not_to have_received(:perform_now)
    end

    # @lat: [[pipeline-bill-stage-status-model#not_run: nothing was produced, but nothing failed]]
    it "records :summarize as not_run when the job produced nothing, so resume comes back for it" do
      run = create(:legislation_pipeline_run)
      bill = create(:bill, external_id: "OWNED-SUMMARIZE-1")
      bill_run = create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
        .and_return(GenerateBillSummaryJob::NOT_RUN)
      job = described_class.new

      result = job.send(:execute_bill_level_service, run, :summarize, bill_run)

      expect(result).to eq(GenerateBillSummaryJob::NOT_RUN)
      # The whole point: whatever the caller writes down, resume must not read
      # it as done.
      bill_run.update!(stage_results: {"summarize" => {"status" => "not_run"}})
      expect(job.send(:stage_already_succeeded?, bill_run, :summarize)).to be(false)
    end

    it "refuses :extract_text when no Bill row resolves, rather than writing only the artifact" do
      with_tmp_legislation_roots("a-wr-04") do |raw_root, text_root|
        ghost_dir = File.join(raw_root, "baltimore-maryland-united_states", "GHOST-EXTRACT-1")
        FileUtils.mkdir_p(ghost_dir)
        File.write(File.join(ghost_dir, "bill.pdf"), "%PDF-1.4")
        run = create(:legislation_pipeline_run)
        bill_run = create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: "GHOST-EXTRACT-1")
        extractor = instance_double(MupdfExtractor, call: "extracted body text")
        allow(MupdfExtractor).to receive(:new).and_return(extractor)

        expect { described_class.new.send(:execute_bill_level_service, run, :extract_text, bill_run) }
          .to raise_error(BillProcessingError, /no Bill row for external_id GHOST-EXTRACT-1/)
        # The .md file is what makes the silence stick. Once written, it tells
        # Pipeline::ArtifactPresence the stage is done — for a bill whose text was
        # never stored anywhere.
        expect(Pathname.glob(File.join(text_root, "**", "GHOST-EXTRACT-1.md"))).to be_empty
      end
    end

    it "still extracts and stores for a bill that does resolve" do
      with_tmp_legislation_roots("a-wr-04-ok") do |raw_root, text_root|
        bill = create(:bill, external_id: "REAL-EXTRACT-1", scheduled_release_date_utc: 310.days.ago)
        real_dir = File.join(raw_root, bill.sway_locale.name, "REAL-EXTRACT-1")
        FileUtils.mkdir_p(real_dir)
        File.write(File.join(real_dir, "bill.pdf"), "%PDF-1.4")
        run = create(:legislation_pipeline_run)
        bill_run = create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: "REAL-EXTRACT-1")
        extractor = instance_double(MupdfExtractor, call: "extracted body text")
        allow(MupdfExtractor).to receive(:new).and_return(extractor)

        described_class.new.send(:execute_bill_level_service, run, :extract_text, bill_run)

        expect(bill.reload.extracted_text).to eq("extracted body text")
        expect(File.read(File.join(text_root, bill.sway_locale.name, "REAL-EXTRACT-1.md")))
          .to eq("extracted body text")
      end
    end
  end

  describe "#perform — 5-consecutive-failure budget" do
    let!(:bill_runs) do
      (1..6).map do |i|
        create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: "BUDGET-#{i}",
          stage_results: {
            "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}
          })
      end
    end

    before do
      bill_runs.each_with_index do |br, i|
        create(:bill, external_id: br.bill_external_id, sway_locale: sway_locale,
          title: "Budget bill #{i}", scheduled_release_date_utc: Time.zone.now - (i + 10).days)
      end
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      allow(ParseSectionsService).to receive(:new).and_raise(BillProcessingError, "always fails")
    end

    it "aborts the stage after 5 consecutive bill failures and emits stage_budget_tripped" do
      expect {
        described_class.new.perform(run.id)
      }.to raise_error(StageError, /aborted after 5 consecutive failures/)

      tripped = PipelineActivityLogEntry.where(event_type: "stage_budget_tripped").last
      expect(tripped).to be_present
      expect(tripped.payload["stage"]).to eq("parse_sections")
      # Only the 5 bills the budget allowed should have failed; the 6th never ran.
      failed_count = bill_runs.count { |br| br.reload.stage_results.dig("parse_sections", "status") == "failed" }
      expect(failed_count).to eq(5)
    end
  end

  describe "#perform — visible bill traversal" do
    # @lat: [[bill-session-archiving-tests#Bill session archive tests#Visible pipeline traversal query budget]]
    it "dispatches unfinished stages without retained archive existence reads" do
      locale = create(:sway_locale)
      live_run = create(:legislation_pipeline_run, sway_locale: locale,
        stages: ["parse-sections"], download_missing_assets: false)
      bills = create_list(:bill, 2, sway_locale: locale, scheduled_release_date_utc: nil)
      rows = bills.map.with_index do |bill, index|
        create(:pipeline_run_bill, legislation_pipeline_run: live_run,
          bill_external_id: bill.external_id, sort_order: index)
      end
      parser = instance_double(ParseSectionsService, call: nil)
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      allow(ParseSectionsService).to receive(:new).and_return(parser)
      archive_reads = [] #: Array[String]
      subscriber = lambda do |*notification_args|
        payload = notification_args.last
        sql = payload[:sql]
        if sql.match?(/SELECT 1 AS one FROM "bills"/i) && sql.match?(/"bills"\."archived_at" IS NOT NULL/i)
          archive_reads << sql
        end
      end

      allow_any_instance_of(described_class).to receive(:run_bill_level_stage).and_wrap_original do |method, *args, **kwargs|
        ActiveRecord::Base.uncached do
          ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
            method.call(*args, **kwargs)
          end
        end
      end
      described_class.new.perform(live_run.id)

      bills.each do |bill|
        expect(ParseSectionsService).to have_received(:new).with(
          bill: bill, bill_run: kind_of(PipelineRunBill), run: kind_of(LegislationPipelineRun)
        ).once
      end
      rows.each do |row|
        expect(row.reload.status).to eq("succeeded")
        expect(row.stage_results.fetch("parse_sections")).to include("status" => "succeeded")
      end
      expect(live_run.reload.status).to eq("succeeded")
      expect(archive_reads).to be_empty
    end
  end

  describe "#perform — missing bill identity" do
    # @lat: [[bill-session-archiving-tests#Bill session archive tests#Missing pipeline identity outcome]]
    it "records the failed stage and concludes the run as partial" do
      missing_run = create(:legislation_pipeline_run, sway_locale: create(:sway_locale),
        stages: ["parse-sections"], download_missing_assets: false)
      row = create(:pipeline_run_bill, legislation_pipeline_run: missing_run,
        bill_external_id: "MISSING-TRAVERSAL")
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      visible_bill = create(:bill, sway_locale: missing_run.sway_locale, scheduled_release_date_utc: nil)
      visible_row = create(:pipeline_run_bill, legislation_pipeline_run: missing_run,
        bill_external_id: visible_bill.external_id, sort_order: 1)
      allow(ParseSectionsService).to receive(:new).and_return(instance_double(ParseSectionsService, call: nil))

      described_class.new.perform(missing_run.id)

      expect(ParseSectionsService).to have_received(:new).once.with(
        bill: visible_bill, bill_run: kind_of(PipelineRunBill), run: kind_of(LegislationPipelineRun)
      )
      expect(visible_row.reload.stage_results.dig("parse_sections", "status")).to eq("succeeded")
      expect(row.reload.stage_results.dig("parse_sections", "status")).to eq("failed")
      expect(row.stage_results.dig("parse_sections", "error")).to include("no Bill row")
      expect(missing_run.reload.status).to eq("partial")
    end
  end

  describe "BLOCKER 3 — TESSDATA_PREFIX preflight" do
    let!(:bill_run) do
      create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: "TESS-TEST",
        stage_results: {})
    end

    before do
      create(:bill, external_id: "TESS-TEST", sway_locale: sway_locale)
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      # The job checks the environment by calling MupdfExtractor.preflight!, a
      # class method that reads ENV, rather than building
      # MupdfExtractor.new("/dev/null"). Faking that class method makes the check
      # raise before any extractor is built.
      allow(MupdfExtractor).to receive(:preflight!).and_raise(
        MupdfExtractor::MissingTessdataError, "TESSDATA_PREFIX is not set"
      )
    end

    it "aborts the extract_text stage at preflight without consuming bill budget" do
      expect { described_class.new.perform(run.id) }
        .to raise_error(StageError, /TESSDATA_PREFIX not set/)
      bill_run.reload
      # No per-bill failure was recorded, because the check stopped the stage first.
      expect(bill_run.stage_results.dig("extract_text", "status")).to be_nil
      expect(run.reload.error_message.to_s).to include("TESSDATA_PREFIX not set")
    end
  end

  # @lat: [[pipeline-run-failure-handling#Preserving the original error through a secondary failure]]
  # Pins: #perform's outer rescue re-raises the ORIGINAL error, not a secondary one raised inside handle_run_failure.
  describe "#perform — handle_run_failure secondary rescue (CG6-02 / ME5-02)" do
    let(:bill) { create(:bill, external_id: "SECONDARY-RESCUE-TEST", sway_locale: sway_locale) }
    let!(:bill_run) do
      create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id,
        stage_results: {"extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}})
    end

    before do
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      # Raise a BillProcessingError mid-stage so the outer rescue goes through
      # handle_run_failure.
      allow(ParseSectionsService).to receive(:new).and_raise(BillProcessingError, "original failure")
      # @lat: [[pipeline-run-failure-handling#Preserving the original error through a secondary failure]]
      allow(SwayLogging).to receive(:error).and_call_original
      allow(SwayLogging).to receive(:error)
        .with("run_legislation_pipeline.failed", anything)
        .and_raise(KeyError, "secondary failure inside handler")
    end

    it "re-raises the ORIGINAL error from perform, not the secondary KeyError" do
      expect {
        described_class.new.perform(run.id)
      }.to raise_error(StageError) do |raised|
        # #perform's outer rescue turns a BillProcessingError into a StageError
        # only when a stage transition is invalid; a plain stage failure is
        # re-raised as it was. Either way, the KeyError must not escape. Ruby
        # only swaps it into a bare `raise` when the rescue body lets it through.
        expect(raised).not_to be_a(KeyError)
        expect(raised.message).not_to include("secondary failure inside handler")
      end
    end

    it "logs the secondary failure at ERROR with BOTH original + secondary classes" do
      logged = [] # steep:ignore
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      expect { described_class.new.perform(run.id) }.to raise_error(StandardError)

      secondary_log = logged.find { |m| m.include?("SECONDARY failure") }
      expect(secondary_log).to be_present,
        "expected Rails.logger.error to log the secondary failure; got: #{logged.inspect}"
      expect(secondary_log).to include("original=")
      expect(secondary_log).to include("secondary=KeyError")
    end
  end

  # @lat: [[pipeline-run-failure-handling#Why spec/system/admin_pipeline_run_controls_spec.rb exists]]
  # Pins: a non-database exception inside handle_run_failure must land in the StandardError clause, not the ActiveRecord one.
  describe "#perform — HI4-01 AR-narrowed rescue (CG6-03)" do
    let(:bill) { create(:bill, external_id: "AR-NARROW-TEST", sway_locale: sway_locale) }
    let!(:bill_run) do
      create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id,
        stage_results: {"extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}})
    end

    before do
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      allow(ParseSectionsService).to receive(:new).and_raise(BillProcessingError, "original failure")
    end

    it "routes a non-AR exception (RuntimeError) inside handle_run_failure to the SECONDARY clause, not the AR clause" do
      # Plant a non-database exception in the handler body through
      # SwayLogging.error, its last statement before the rescue clauses.
      allow(SwayLogging).to receive(:error).and_call_original
      allow(SwayLogging).to receive(:error)
        .with("run_legislation_pipeline.failed", anything)
        .and_raise(RuntimeError, "non-AR secondary failure")

      logged = [] # steep:ignore
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      expect { described_class.new.perform(run.id) }.to raise_error(StandardError)

      # The non-database exception has to be logged by the second clause, whose
      # line carries the "SECONDARY failure" marker and the original= context.
      secondary_log = logged.find { |m| m.include?("SECONDARY failure") }
      expect(secondary_log).to be_present,
        "expected the ME5-02 secondary clause to handle the non-AR exception; got: #{logged.inspect}"
      expect(secondary_log).to include("secondary=RuntimeError")

      # The database-only clause must not have fired, so there is no
      # "failure handler AR error" line.
      ar_log = logged.find { |m| m.include?("failure handler AR error") }
      expect(ar_log).to be_nil,
        "expected the HI4-01 AR-only clause to NOT have caught a RuntimeError; got: #{logged.inspect}"
    end

    it "routes an ActiveRecord::ActiveRecordError inside handle_run_failure to the AR clause, not the SECONDARY clause" do
      allow(SwayLogging).to receive(:error).and_call_original
      allow(SwayLogging).to receive(:error)
        .with("run_legislation_pipeline.failed", anything)
        .and_raise(ActiveRecord::RecordInvalid.new(LegislationPipelineRun.new))

      logged = [] # steep:ignore
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      expect { described_class.new.perform(run.id) }.to raise_error(StandardError)

      # A database error must hit the narrowed clause first, since it comes
      # before the StandardError clause in the source.
      ar_log = logged.find { |m| m.include?("failure handler AR error") }
      expect(ar_log).to be_present,
        "expected the HI4-01 AR-only clause to handle ActiveRecord::RecordInvalid; got: #{logged.inspect}"
      expect(ar_log).to include("ActiveRecord::RecordInvalid")

      # The second clause must not fire for a database error.
      secondary_log = logged.find { |m| m.include?("SECONDARY failure") }
      expect(secondary_log).to be_nil,
        "expected the ME5-02 secondary clause to NOT catch an AR error; got: #{logged.inspect}"
    end
  end

  describe "limits_concurrency declaration" do
    # @lat: [[legislation-pipeline-lock-duration#What duration: actually controls]]
    # The exact match is deliberate: change only with a new decision, not by drift.
    it "holds the lock for exactly 4 hours" do
      duration = described_class.new.concurrency_duration
      expect(duration).to be_a(ActiveSupport::Duration)
      expect(duration).to eq(4.hours)
    end
  end

  # @lat: [[stages-to-run-algorithm#Where the artifact-aware skip lives]]
  describe "stages_to_run honors run.stages" do
    let(:job) { described_class.new }

    it "returns the literal selection in DAG order when dma=false" do
      run.update!(stages: %w[extract-text parse-sections], download_missing_assets: false)
      result = job.send(:stages_to_run, run, "fresh")
      expect(result).to eq([:extract_text, :parse_sections])
    end

    it "includes the full transitive closure when dma=true via Pipeline::StageDeps.transitive_closure" do
      run.update!(stages: %w[summarize-bill], download_missing_assets: true)
      result = job.send(:stages_to_run, run, "fresh")
      # what depends on what: summarize-bill → generate-diffs → parse-sections
      # → (extract-text, fetch-law) → fetch-bills; and summarize-bill →
      # fetch-hearings → clean-testimony
      expect(result).to eq([
        :fetch_bills, :fetch_law, :extract_text, :parse_sections,
        :generate_diffs, :fetch_hearings, :clean_testimony, :summarize
      ])
    end

    it "literal selection is unchanged when dma=true does not pull new upstream deps" do
      run.update!(stages: %w[fetch-bills fetch-law], download_missing_assets: true)
      result = job.send(:stages_to_run, run, "fresh")
      expect(result).to eq([:fetch_bills, :fetch_law])
    end

    # @lat: [[resume-stage-history-walk#Why the "filters out stages the resumed run already finished" fixture puts the succeeded row on the PARENT run]]
    it "filters out stages the resumed run already finished" do
      parent = create(
        :legislation_pipeline_run,
        stages: %w[fetch-bills extract-text parse-sections],
        download_missing_assets: false,
        status: "failed"
      )
      PipelineRunStage.create!(
        legislation_pipeline_run: parent, stage_name: "fetch_bills", status: "succeeded"
      )
      resumed = create(
        :legislation_pipeline_run,
        stages: %w[fetch-bills extract-text parse-sections],
        download_missing_assets: false,
        origin: "resume",
        parent_run_id: parent.id.to_s
      )

      # No stages on the resume row itself. That is what production hands the
      # job, and reading it is what the defect did.
      expect(resumed.pipeline_run_stages).to be_empty

      expect(job.send(:stages_to_run, resumed, "resume")).to eq([:extract_text, :parse_sections])
    end

    # A resume of a resume. The middle run holds only what ITS attempt
    # finished, so one level up is not enough.
    it "filters out stages finished anywhere earlier in the resume chain" do
      first = create(
        :legislation_pipeline_run,
        stages: %w[fetch-bills extract-text parse-sections],
        download_missing_assets: false,
        status: "failed"
      )
      PipelineRunStage.create!(
        legislation_pipeline_run: first, stage_name: "fetch_bills", status: "succeeded"
      )
      second = create(
        :legislation_pipeline_run,
        stages: %w[fetch-bills extract-text parse-sections],
        download_missing_assets: false,
        origin: "resume",
        parent_run_id: first.id.to_s,
        status: "failed"
      )
      PipelineRunStage.create!(
        legislation_pipeline_run: second, stage_name: "extract_text", status: "succeeded"
      )
      third = create(
        :legislation_pipeline_run,
        stages: %w[fetch-bills extract-text parse-sections],
        download_missing_assets: false,
        origin: "resume",
        parent_run_id: second.id.to_s
      )

      expect(job.send(:stages_to_run, third, "resume")).to eq([:parse_sections])
    end

    # A stage that failed is not a stage that finished.
    it "keeps a stage the resumed run did not finish" do
      parent = create(
        :legislation_pipeline_run,
        stages: %w[fetch-bills extract-text],
        download_missing_assets: false,
        status: "failed"
      )
      PipelineRunStage.create!(
        legislation_pipeline_run: parent, stage_name: "fetch_bills", status: "failed"
      )
      resumed = create(
        :legislation_pipeline_run,
        stages: %w[fetch-bills extract-text],
        download_missing_assets: false,
        origin: "resume",
        parent_run_id: parent.id.to_s
      )

      expect(job.send(:stages_to_run, resumed, "resume")).to eq([:fetch_bills, :extract_text])
    end
  end

  describe "per-bill artifact-aware skip gate" do
    let(:bill) { create(:bill, external_id: "GATE-BILL-1", sway_locale: sway_locale) }
    let!(:bill_run) do
      create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: bill.external_id,
        stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
    end

    before do
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
    end

    it "skips an AUTO-INCLUDED stage for a bill that already has the artifact" do
      # download_missing_assets is on, so parse-sections comes along as a
      # dependency. The bill already has BillSectionReference rows, so it is
      # skipped.
      run.update!(stages: %w[generate-diffs], download_missing_assets: true)
      create(:bill_section_reference, bill: bill)
      # Mark generate-diffs done up front so the stage the operator ticked does
      # not really call GenerateDiffsService. The point here is how a
      # pulled-in parse-sections decides to skip.
      bill_run.update!(stage_results: bill_run.stage_results.merge(
        "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "summarize" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "generate_diffs" => {"status" => "succeeded", "at" => Time.current.iso8601}
      ))
      # ParseSectionsService should never be built. Check that, and that
      # parse_sections is written down as skipped.
      expect(ParseSectionsService).not_to receive(:new)

      described_class.new.perform(run.id)

      bill_run.reload
      expect(bill_run.stage_results.dig("parse_sections", "status")).to eq("skipped")
      expect(bill_run.stage_results.dig("parse_sections", "reason")).to eq("artifact_present")
    end

    it "runs an AUTO-INCLUDED stage for a bill that does NOT have the artifact" do
      # download_missing_assets pulls parse-sections in, and this bill has no
      # section rows yet.
      run.update!(stages: %w[generate-diffs], download_missing_assets: true)
      bill_run.update!(stage_results: bill_run.stage_results.merge(
        "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "summarize" => {"status" => "succeeded", "at" => Time.current.iso8601},
        "generate_diffs" => {"status" => "succeeded", "at" => Time.current.iso8601}
      ))
      stub_ps = instance_double(ParseSectionsService, call: nil)
      allow(ParseSectionsService).to receive(:new).and_return(stub_ps)

      described_class.new.perform(run.id)

      expect(stub_ps).to have_received(:call)
      bill_run.reload
      expect(bill_run.stage_results.dig("parse_sections", "status")).to eq("succeeded")
    end

    # A stage the operator ticked runs for every bill no matter what, even when
    # the output already exists.
    context "regression: operator-override invariant" do
      it "summarize-bill operator-checked still runs for a bill with bill_llm_provisioning.llm_summary present" do
        # The operator ticked summarize-bill, so it runs even though a summary exists.
        create(:bill_llm_provisioning, bill: bill, llm_summary: "already done")
        run.update!(stages: %w[summarize-bill], download_missing_assets: false)
        bill_run.update!(stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "parse_sections" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "generate_diffs" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
        invoked_for = [] # steep:ignore
        allow(GenerateBillSummaryJob).to receive(:perform_now) { |bid| invoked_for << bid }

        described_class.new.perform(run.id)

        expect(invoked_for).to include(bill.id)
      end

      it "generate-diffs AUTO-INCLUDED with artifact present SKIPS the bill (proves gate is auto_included && present?)" do
        # The operator ticked summarize-bill, not generate-diffs. generate-diffs
        # comes along as a dependency, and the bill already has diff_content.
        # Pulled in automatically plus output already there means skip.
        create(:bill_llm_provisioning, bill: bill, diff_content: "already")
        run.update!(stages: %w[summarize-bill], download_missing_assets: true)
        bill_run.update!(stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "parse_sections" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "summarize" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
        expect(GenerateDiffsService).not_to receive(:new)

        described_class.new.perform(run.id)

        bill_run.reload
        expect(bill_run.stage_results.dig("generate_diffs", "status")).to eq("skipped")
        expect(bill_run.stage_results.dig("generate_diffs", "reason")).to eq("artifact_present")
      end
    end

    # How Pipeline::Current.current_auto_include_context is wired up. The job
    # SETS it just before a pulled-in stage calls start_<stage>!, and CLEARS it
    # in an ensure block after complete_<stage>!. A stage the operator ticked
    # leaves it nil.
    context "Pipeline::Current auto-include plumbing (FINDING-1)" do
      it "leaves Pipeline::Current.current_auto_include_context NIL for OPERATOR-CHECKED stages" do
        run.update!(stages: %w[summarize-bill], download_missing_assets: false)
        bill_run.update!(stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "parse_sections" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "generate_diffs" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
        observed_at_summarize_start = nil #: Hash[Symbol, untyped]?
        allow(GenerateBillSummaryJob).to receive(:perform_now) do |_bid|
          observed_at_summarize_start = Pipeline::Current.current_auto_include_context
        end

        described_class.new.perform(run.id)

        expect(observed_at_summarize_start).to be_nil
      end

      it "POPULATES Pipeline::Current.current_auto_include_context for AUTO-INCLUDED stages" do
        run.update!(stages: %w[summarize-bill], download_missing_assets: true)
        # The bill must have no diff_content, so generate-diffs is pulled in and
        # then actually runs instead of being skipped.
        bill_run.update!(stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "parse_sections" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "summarize" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
        observed = nil #: Hash[Symbol, untyped]?
        allow(GenerateDiffsService).to receive(:new) do |**_kwargs|
          observed = Pipeline::Current.current_auto_include_context
          instance_double(GenerateDiffsService, call: nil)
        end

        described_class.new.perform(run.id)

        expect(observed).to be_a(Hash)
        expect(observed&.dig(:stage)).to eq("generate-diffs")
        expect(observed&.dig(:reason)).to eq("missing_artifact")
        expect(observed&.dig(:bill_external_ids)).to include(bill.external_id)
      end

      it "CLEARS Pipeline::Current.current_auto_include_context after the stage completes (ensure-block)" do
        run.update!(stages: %w[summarize-bill], download_missing_assets: true)
        bill_run.update!(stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "parse_sections" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "summarize" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
        allow(GenerateDiffsService).to receive(:new).and_return(instance_double(GenerateDiffsService, call: nil))

        described_class.new.perform(run.id)

        expect(Pipeline::Current.current_auto_include_context).to be_nil
      end
    end

    # The job builds FetchBillsService with mode: :discover when the operator
    # ticked fetch-bills, and with mode: :backfill_missing when the stage was
    # pulled in as a dependency.
    context "service_mode_for dispatch — fetch-bills (Task 5 wiring)" do
      let(:canonical_dir) { Rails.root.join("legislation/bills/raw/#{bill.sway_locale.name}/#{bill.external_id}") }

      it "constructs FetchBillsService with mode: :backfill_missing when fetch-bills is AUTO-INCLUDED" do
        run.update!(stages: %w[extract-text], download_missing_assets: true)
        # extract-text depends on fetch-bills, so fetch-bills is pulled in.
        bill_run.update!(stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "parse_sections" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "generate_diffs" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "fetch_hearings" => {"status" => "succeeded", "at" => Time.current.iso8601},
          "summarize" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
        observed_modes = [] # steep:ignore
        allow(FetchBillsService).to receive(:new) do |**kwargs|
          observed_modes << kwargs[:mode]
          instance_double(FetchBillsService, call: [])
        end

        described_class.new.perform(run.id)

        expect(observed_modes).to include(:backfill_missing)
      end

      it "constructs FetchBillsService with mode: :discover when fetch-bills is OPERATOR-CHECKED (even if bills have PDFs already)" do
        # The PDF already sits at its usual path. Because the operator ticked the
        # stage, fetch-bills still runs, in :discover mode.
        FileUtils.mkdir_p(canonical_dir)
        File.binwrite(canonical_dir.join("existing.pdf"), "%PDF-FAKE")
        run.update!(stages: %w[fetch-bills], download_missing_assets: false)
        observed_modes = [] # steep:ignore
        allow(FetchBillsService).to receive(:new) do |**kwargs|
          observed_modes << kwargs[:mode]
          instance_double(FetchBillsService, call: [])
        end

        begin
          described_class.new.perform(run.id)
        rescue StageError
          # Expected. No per-bill stage ran, so the "nothing succeeded" guard
          # fires. All that matters here is that FetchBillsService was built with
          # the right mode before the run failed.
        end

        expect(observed_modes).to eq([:discover])
      ensure
        FileUtils.rm_rf(canonical_dir.to_s)
      end
    end

    # parse-sections with no section_index.json must not quietly do nothing.
    # With download_missing_assets on, fetch-law is pulled in and runs, which
    # produces that file. With it off, a BillProcessingError surfaces loudly.
    context "regression: silent no-op" do
      it "auto-runs fetch-law when dma=true and parse-sections is checked without section_index.json" do
        run.update!(stages: %w[parse-sections], download_missing_assets: true)
        bill_run.update!(stage_results: {
          "extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}
        })
        # :fetch_law must be pulled in, because parse-sections depends on it.
        result = described_class.new.send(:stages_to_run, run.reload, "fresh")
        expect(result).to include(:fetch_law)
        expect(result).to include(:fetch_bills)
      end

      it "surfaces BillProcessingError when dma=false and parse-sections runs without extract-text" do
        run.update!(stages: %w[parse-sections], download_missing_assets: false)
        # The bill has no extracted_text, so parse-sections fails inside the
        # service. Check that the job runs only the stage that was ticked, does
        # not pull fetch-law in, and lets a per-bill BillProcessingError surface.
        result = described_class.new.send(:stages_to_run, run.reload, "fresh")
        expect(result).to eq([:parse_sections])
        # fetch-law is not pulled in, so there is no quiet rescue path
        expect(result).not_to include(:fetch_law)
      end
    end
  end

  # @lat: [[pipeline-run-bills-seeding#Single-bill runs]]
  describe "#perform — single-bill pre-seed pipeline_run_bills" do
    let(:single_bill) do
      create(:bill,
        external_id: "SWAY-V170-PRESEED",
        sway_locale: sway_locale)
    end

    it "seeds a pipeline_run_bills row from run.bill_id when stages exclude fetch-bills" do
      run = create(:legislation_pipeline_run,
        bill: single_bill,
        stages: %w[extract-text parse-sections generate-diffs fetch-hearings summarize-bill],
        download_missing_assets: false,
        status: "queued")

      expect(run.pipeline_run_bills.count).to eq(0)

      # Make every stage do nothing, so the job walks cleanly through them. The
      # row created up front satisfies the "something succeeded" gate, either via
      # the already-has-the-output skip or via the faked per-bill service.
      allow_any_instance_of(described_class).to receive(:execute_bill_level_service).and_return(nil)
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)

      described_class.new.perform(run.id)

      run.reload
      expect(run.pipeline_run_bills.count).to eq(1)
      seeded = run.pipeline_run_bills.first
      expect(seeded.bill_external_id).to eq(single_bill.external_id)
    end

    it "seeds the PRB row on restart of a single-bill run (UAT-3 / parent #10 reproducer)" do
      parent = create(:legislation_pipeline_run,
        bill: single_bill,
        stages: %w[extract-text parse-sections generate-diffs fetch-hearings summarize-bill],
        download_missing_assets: false,
        status: "failed")

      restart_run = create(:legislation_pipeline_run,
        bill: single_bill,
        stages: parent.stages,
        download_missing_assets: parent.download_missing_assets,
        status: "queued",
        parent_run_id: parent.id.to_s,
        origin: "restart")

      expect(restart_run.pipeline_run_bills.count).to eq(0)

      allow_any_instance_of(described_class).to receive(:execute_bill_level_service).and_return(nil)
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)

      described_class.new.perform(restart_run.id, origin: "restart")

      restart_run.reload
      expect(restart_run.pipeline_run_bills.count).to eq(1)
      expect(restart_run.pipeline_run_bills.first.bill_external_id)
        .to eq(single_bill.external_id)
    end

    it "is a no-op for all-bills runs (run.bill_id nil) — does NOT inject a phantom PRB row" do
      run = create(:legislation_pipeline_run,
        bill: nil,
        stages: %w[fetch-bills extract-text],
        download_missing_assets: true,
        status: "queued")

      expect(run.bill_id).to be_nil
      expect(run.pipeline_run_bills.count).to eq(0)

      # @lat: [[pipeline-run-bills-seeding#Why the all-bills-runs spec swallows the StageError that follows]]
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow_any_instance_of(described_class).to receive(:execute_bill_level_service).and_return(nil)
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)

      begin
        described_class.new.perform(run.id)
      rescue
        nil
      end

      run.reload
      # The seeding helper must not invent a row when run.bill_id is nil. The
      # count is whatever fetch-bills produced — 0 here, since the faked service
      # returned nothing — and not 1 from the seeding step.
      expect(run.pipeline_run_bills.count).to eq(0)
    end

    it "is idempotent on re-perform (resume / restart cycles do not duplicate the PRB row)" do
      run = create(:legislation_pipeline_run,
        bill: single_bill,
        stages: %w[extract-text summarize-bill],
        download_missing_assets: false,
        status: "queued")

      # A row left behind by an earlier call to perform.
      existing = create(:pipeline_run_bill,
        legislation_pipeline_run: run,
        bill_external_id: single_bill.external_id,
        stage_results: {"extract_text" => {"status" => "succeeded", "at" => Time.current.iso8601}})

      allow_any_instance_of(described_class).to receive(:execute_bill_level_service).and_return(nil)
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)

      described_class.new.perform(run.id, origin: "resume")

      run.reload
      expect(run.pipeline_run_bills.count).to eq(1)
      expect(run.pipeline_run_bills.first.id).to eq(existing.id)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Why resume draws the same line as abandonment]]
  describe "#normalize_for_resume — awaiting_summary_batch" do
    subject(:job) { described_class.new }

    before do
      allow(PipelineActivityLogger).to receive(:emit_state_transition!).and_call_original
    end

    it "leaves the run waiting and logs a deferral while the batch has not expired" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: 1.hour.from_now)
      batch_ids = run.pipeline_run_summary_batches.map(&:batch_id)

      expect(job.send(:normalize_for_resume, run)).to be(true)

      run.reload
      expect(run.status).to eq("awaiting_summary_batch")
      expect(run.pipeline_run_summary_batches.map(&:batch_id)).to eq(batch_ids)

      entry = PipelineActivityLogEntry.where(event_type: "resume_deferred_for_summary_batch").last
      entry ||= raise("expected a resume_deferred_for_summary_batch entry")
      expect(entry.subject).to eq(run)
      expect(entry.severity).to eq("info")
    end

    it "does not reopen the stuck stage while the batch has not expired" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: 1.hour.from_now)
      stage = create(:pipeline_run_stage, legislation_pipeline_run: run, stage_name: "summarize", status: "running")

      job.send(:normalize_for_resume, run)

      expect(stage.reload.status).to eq("running")
    end

    it "normalizes as before once the batch's expiry has passed" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: 1.minute.ago)
      stage = create(:pipeline_run_stage, legislation_pipeline_run: run, stage_name: "summarize", status: "running")

      expect(job.send(:normalize_for_resume, run)).to be(false)

      run.reload
      expect(run.status).to eq("running")
      expect(stage.reload.status).to eq("pending")
      expect(PipelineActivityLogEntry.where(event_type: "resume_deferred_for_summary_batch")).to be_empty
    end

    it "normalizes as before when the batch never recorded an expiry" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: nil)

      expect(job.send(:normalize_for_resume, run)).to be(false)
      expect(run.reload.status).to eq("running")
    end

    it "leaves perform's stage loop untouched for a run deferred on a live batch" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: 1.hour.from_now)

      expect(FetchBillsService).not_to receive(:new)

      job.perform(run.id, origin: "resume")

      expect(run.reload.status).to eq("awaiting_summary_batch")
    end
  end

  # @lat: [[pipeline-run-partial-vs-succeeded#Guaranteeing a terminal state]]
  describe "#finalize_run_terminal_state — guarantees terminal state" do
    let(:job) { described_class.new }

    it "marks succeeded when can_mark_succeeded? is true and no bills failed" do
      run = create(:legislation_pipeline_run, status: "queued")
      run.start_running!

      job.send(:finalize_run_terminal_state, run)

      expect(run.reload.status).to eq("succeeded")
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
    LegislationPipelineRun::PHASE_52_STAGE_STATES.each do |stuck_state|
      it "force-fails when DAG loop returns with run stuck in :#{stuck_state}" do
        run = create(:legislation_pipeline_run, status: "queued")
        # Write the status straight to the column, going around the state
        # machine, to recreate the stuck-mid-stage shape a sleeping dev machine
        # produced.
        run.update_columns(status: stuck_state.to_s)

        allow(SwayLogging).to receive(:error)

        job.send(:finalize_run_terminal_state, run)

        expect(run.reload.status).to eq("failed")
        expect(run.error_message).to be_present
        expect(run.error_message).to include(stuck_state.to_s)
        expect(SwayLogging).to have_received(:error).with(
          "run_legislation_pipeline.non_terminal_at_finalize",
          hash_including(run_id: run.id, status: stuck_state.to_s)
        )
      end
    end

    it "leaves a run that is already terminal-failed alone (idempotent)" do
      run = create(:legislation_pipeline_run, status: "queued")
      run.update_columns(status: "failed", error_message: "preexisting")

      expect(SwayLogging).not_to receive(:error).with(
        "run_legislation_pipeline.non_terminal_at_finalize", anything
      )

      job.send(:finalize_run_terminal_state, run)

      expect(run.reload.status).to eq("failed")
      expect(run.error_message).to eq("preexisting")
    end

    it "leaves a run that is already terminal-succeeded alone (idempotent)" do
      run = create(:legislation_pipeline_run, status: "queued")
      run.update_columns(status: "succeeded")

      expect(SwayLogging).not_to receive(:error).with(
        "run_legislation_pipeline.non_terminal_at_finalize", anything
      )

      job.send(:finalize_run_terminal_state, run)

      expect(run.reload.status).to eq("succeeded")
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Submitting a run's summarisation as chunked batches]]
  describe "#perform — the summarize stage of a full run submits batches" do
    around { |example| with_app_config(:llm, llm_provider: "claude") { example.run } }

    let(:batch_expires_at) { 23.hours.from_now.change(usec: 0) }

    def seed_through_clean_testimony
      %w[extract_text parse_sections generate_diffs fetch_hearings clean_testimony]
        .index_with { {"status" => "succeeded", "at" => Time.current.iso8601} }
    end

    def batch_bill(external_id, days_ago, text: "Section 1. The Mayor shall report annually.")
      bill = create(:bill, external_id: external_id, sway_locale: sway_locale,
        extracted_text: text, scheduled_release_date_utc: days_ago.days.ago)
      create(:bill_llm_provisioning, :with_testimony, bill: bill)
      create(:pipeline_run_bill, legislation_pipeline_run: run,
        bill_external_id: bill.external_id, stage_results: seed_through_clean_testimony)
      bill
    end

    before do
      AdminSetting.singleton.update!(summary_batch_enabled: true)
      allow(FetchBillsService).to receive(:new).and_return(instance_double(FetchBillsService, call: []))
      allow(FetchLawService).to receive(:new).and_return(instance_double(FetchLawService, call: {}))
      allow_any_instance_of(described_class).to receive(:preflight_stage_environment!)
      allow(GenerateBillSummaryJob).to receive(:perform_now)
      allow(Llm::ClaudeBatchService).to receive(:submit)
        .and_return(double(id: "msgbatch_pipeline", expires_at: batch_expires_at))
    end

    it "submits the stage's work instead of walking bills through the synchronous job" do
      batch_bill("PB-BATCH-1", 601)

      described_class.new.perform(run.id)

      expect(GenerateBillSummaryJob).not_to have_received(:perform_now)
    end

    it "returns with the run waiting on its batches rather than finalized" do
      batch_bill("PB-BATCH-2", 602)

      described_class.new.perform(run.id)

      expect(run.reload.status).to eq("awaiting_summary_batch")
    end

    it "records one batch row carrying the expiry the API returned" do
      batch_bill("PB-BATCH-3", 603)

      described_class.new.perform(run.id)

      expect(run.pipeline_run_summary_batches.pluck(:batch_id)).to eq(["msgbatch_pipeline"])
    end

    it "records each submitted bill's summarize stage as awaiting_batch" do
      bill = batch_bill("PB-BATCH-4", 604)

      described_class.new.perform(run.id)

      bill_run = run.pipeline_run_bills.find_by(bill_external_id: bill.external_id)
      expect(bill_run.stage_results.dig("summarize", "status")).to eq("awaiting_batch")
    end

    it "does not abort the stage on the zero-succeeded check when every bill is awaiting_batch" do
      batch_bill("PB-BATCH-5", 605)
      batch_bill("PB-BATCH-6", 606)

      expect { described_class.new.perform(run.id) }.not_to raise_error
    end

    it "records a bill that earned no item as skipped, and submits nothing for it" do
      bill = create(:bill, external_id: "PB-BATCH-7", sway_locale: sway_locale,
        extracted_text: nil, scheduled_release_date_utc: 607.days.ago)
      create(:bill_llm_provisioning, bill: bill)
      create(:pipeline_run_bill, legislation_pipeline_run: run,
        bill_external_id: bill.external_id, stage_results: seed_through_clean_testimony)

      described_class.new.perform(run.id)

      bill_run = run.pipeline_run_bills.find_by(bill_external_id: bill.external_id)
      expect(bill_run.stage_results.dig("summarize", "status")).to eq("skipped")
      expect(Llm::ClaudeBatchService).not_to have_received(:submit)
    end

    it "finalizes the run normally when no bill earned an item, since nothing is being waited on" do
      bill = create(:bill, external_id: "PB-BATCH-8", sway_locale: sway_locale,
        extracted_text: nil, scheduled_release_date_utc: 608.days.ago)
      create(:bill_llm_provisioning, bill: bill)
      create(:pipeline_run_bill, legislation_pipeline_run: run,
        bill_external_id: bill.external_id, stage_results: seed_through_clean_testimony)

      described_class.new.perform(run.id)

      expect(run.reload.status).to eq("succeeded")
    end

    it "fails the stage on the first refused submit, rather than spending a failure budget" do
      batch_bill("PB-BATCH-9", 609)
      allow(Llm::ClaudeBatchService).to receive(:submit).and_raise(Llm::TransportError, "model refused")

      expect { described_class.new.perform(run.id) }
        .to raise_error(StageError, /batch submit failed/)
    end

    it "keeps the synchronous walk for a single-bill run" do
      bill = batch_bill("PB-BATCH-10", 610)
      single = create(:legislation_pipeline_run, bill: bill)
      create(:pipeline_run_bill, legislation_pipeline_run: single,
        bill_external_id: bill.external_id, stage_results: seed_through_clean_testimony)

      described_class.new.perform(single.id)

      expect(GenerateBillSummaryJob).to have_received(:perform_now).with(bill.id)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Why a submitted item is a verdict, not a silence]]
  describe "#stage_already_succeeded? — awaiting_batch is not done" do
    subject(:job) { described_class.new }

    it "comes back for a bill whose items expired in a batch that never returned" do
      bill_run = create(:pipeline_run_bill, legislation_pipeline_run: run,
        stage_results: {"summarize" => {"status" => "awaiting_batch", "at" => Time.current.iso8601}})

      expect(job.send(:stage_already_succeeded?, bill_run, :summarize)).to be(false)
    end

    it "still treats a succeeded bill as done" do
      bill_run = create(:pipeline_run_bill, legislation_pipeline_run: run,
        stage_results: {"summarize" => {"status" => "succeeded", "at" => Time.current.iso8601}})

      expect(job.send(:stage_already_succeeded?, bill_run, :summarize)).to be(true)
    end
  end

  describe "Cross-locale pipeline integration" do
    let(:baltimore) { create(:sway_locale, :baltimore) }
    let(:maryland) { create(:sway_locale, :maryland) }
    let(:congress) { create(:sway_locale, :congress) }

    describe "representative single-bill pipeline runs" do
      it "successfully runs an amending Baltimore bill through extract-text, parse-sections, and generate-diffs" do
        with_tmp_legislation_roots("xlocale-balt-1") do |_raw_root, _text_root|
          sec = create(:law_section,
            sway_locale: baltimore,
            key: "art_1__sec_5",
            article: "1",
            section: "5",
            title: "General Provisions")
          bill = create(:bill,
            sway_locale: baltimore,
            external_id: "BALT-AMEND-1",
            extracted_text: "City Code: § 1-5 is hereby repealed.")

          run = create(:legislation_pipeline_run,
            bill: bill,
            sway_locale: baltimore,
            download_missing_assets: false,
            stages: %w[extract-text parse-sections generate-diffs])
          create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)

          described_class.new.perform(run.id)

          expect(run.reload.status).to eq("succeeded")

          # Verify text artifact
          text_path = Legislation::Paths.bill_text_file(bill.external_id, sway_locale: baltimore.name)
          expect(File.exist?(text_path)).to be(true)

          # Verify parsed sections targeting Baltimore LawSection
          refs = BillSectionReference.where(bill_id: bill.id)
          expect(refs.count).to eq(1)
          expect(refs.first.resolution).to eq("exact")
          ops = BillAmendmentOperation.where(bill_id: bill.id)
          expect(ops.first&.target_law_section_id).to eq(sec.id)

          # Verify diff artifact
          expect(bill.reload.bill_llm_provisioning&.diff_content).to be_present
        end
      end

      it "successfully runs an amending Maryland bill through extract-text, parse-sections, and generate-diffs" do
        with_tmp_legislation_roots("xlocale-md-1") do |_raw_root, _text_root|
          sec = create(:law_section,
            sway_locale: maryland,
            key: "art_Transportation__sec_21-801",
            article: "Transportation",
            section: "21-801",
            title: "Speed limits")
          create(:law_section,
            sway_locale: baltimore,
            key: "art_Transportation__sec_21-801",
            article: "Transportation",
            section: "21-801",
            title: "Baltimore decoy")

          md_text = <<~TEXT
            A BILL ENTITLED
            AN ACT concerning Transportation
            BY repealing and reenacting, with amendments,
            Article - Transportation
            Section 21-801
            Annotated Code of Maryland
            SECTION 1. Article - Transportation, Section 21-801 is hereby amended to read as follows:
          TEXT

          bill = create(:bill,
            sway_locale: maryland,
            external_id: "MD-AMEND-1",
            extracted_text: md_text)

          run = create(:legislation_pipeline_run,
            bill: bill,
            sway_locale: maryland,
            download_missing_assets: false,
            stages: %w[extract-text parse-sections generate-diffs])
          create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)

          described_class.new.perform(run.id)

          expect(run.reload.status).to eq("succeeded")

          # Text artifact in Maryland directory
          text_path = Legislation::Paths.bill_text_file(bill.external_id, sway_locale: maryland.name)
          expect(File.exist?(text_path)).to be(true)

          # Parsed section resolved to Maryland LawSection, not Baltimore
          ops = BillAmendmentOperation.where(bill_id: bill.id)
          expect(ops.first&.target_law_section_id).to eq(sec.id)

          # Diff artifact written
          expect(bill.reload.bill_llm_provisioning&.diff_content).to be_present
        end
      end

      it "successfully runs an amending US Congress bill through extract-text, parse-sections, and generate-diffs" do
        with_tmp_legislation_roots("xlocale-us-1") do |_raw_root, _text_root|
          sec = create(:law_section,
            sway_locale: congress,
            key: "art_42__sec_1983",
            article: "42",
            section: "1983",
            title: "Civil rights")
          create(:law_section,
            sway_locale: baltimore,
            key: "art_42__sec_1983",
            article: "42",
            section: "1983",
            title: "Baltimore decoy")

          us_text = <<~TEXT
            A BILL
            To amend title 42, United States Code.
            SEC. 2. Section 1983 of title 42, United States Code, is hereby amended to read as follows:
          TEXT

          bill = create(:bill,
            sway_locale: congress,
            external_id: "US-AMEND-1",
            extracted_text: us_text)

          run = create(:legislation_pipeline_run,
            bill: bill,
            sway_locale: congress,
            download_missing_assets: false,
            stages: %w[extract-text parse-sections generate-diffs])
          create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)

          described_class.new.perform(run.id)

          expect(run.reload.status).to eq("succeeded")

          # Text artifact in Congress directory
          text_path = Legislation::Paths.bill_text_file(bill.external_id, sway_locale: congress.name)
          expect(File.exist?(text_path)).to be(true)

          # Parsed section resolved to Congress LawSection, not Baltimore
          ops = BillAmendmentOperation.where(bill_id: bill.id)
          expect(ops.first&.target_law_section_id).to eq(sec.id)

          # Diff artifact written
          expect(bill.reload.bill_llm_provisioning&.diff_content).to be_present
        end
      end

      it "successfully runs non-amending bills for Maryland and Congress with 0 diff modifications" do
        with_tmp_legislation_roots("xlocale-nonamend-1") do |_raw_root, _text_root|
          md_resolution = create(:bill,
            sway_locale: maryland,
            external_id: "MD-RES-1",
            extracted_text: "SENATE RESOLUTION 1. Congratulating the champion team.")
          us_resolution = create(:bill,
            sway_locale: congress,
            external_id: "US-RES-1",
            extracted_text: "H. RES. 1. Expressing the sense of the House regarding national day of service.")

          [md_resolution, us_resolution].each do |res_bill|
            run = create(:legislation_pipeline_run,
              bill: res_bill,
              sway_locale: res_bill.sway_locale,
              download_missing_assets: false,
              stages: %w[extract-text parse-sections generate-diffs])
            create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: res_bill.external_id)

            described_class.new.perform(run.id)

            expect(run.reload.status).to eq("succeeded")
            expect(BillSectionReference.where(bill_id: res_bill.id)).to be_empty
            expect(BillAmendmentOperation.where(bill_id: res_bill.id)).to be_empty

            diff_data = JSON.parse(res_bill.reload.bill_llm_provisioning.diff_content)
            expect(diff_data["stats"]["sections_modified"]).to eq(0)
            expect(diff_data["stats"]["total_operations"]).to eq(0)
          end
        end
      end
    end

    describe "All bills scope isolation across colliding external IDs" do
      it "isolates All bills execution strictly to the run SwayLocale" do
        with_tmp_legislation_roots("xlocale-scope-1") do |_raw_root, _text_root|
          # Three bills with the same external_id across different locales
          md_bill = create(:bill,
            sway_locale: maryland,
            external_id: "COLLIDE-100",
            extracted_text: "Maryland text")
          _balt_bill = create(:bill,
            sway_locale: baltimore,
            external_id: "COLLIDE-100",
            extracted_text: "Baltimore text")
          _us_bill = create(:bill,
            sway_locale: congress,
            external_id: "COLLIDE-100",
            extracted_text: "Congress text")

          run = create(:legislation_pipeline_run,
            bill: nil,
            sway_locale: maryland,
            download_missing_assets: false,
            stages: %w[extract-text])

          job = described_class.new
          # Perform the job, which hydrates bills for maryland
          job.perform(run.id)

          expect(run.reload.status).to eq("succeeded")
          run_bills = run.pipeline_run_bills
          expect(run_bills.count).to eq(1)
          expect(run_bills.first.bill_external_id).to eq("COLLIDE-100")
          resolved = job.send(:resolve_bill, run_bills.first)
          expect(resolved.id).to eq(md_bill.id)
          expect(resolved.sway_locale_id).to eq(maryland.id)
        end
      end
    end

    describe "Upstream stage dispatch without Baltimore fallback" do
      around do |example|
        with_tmp_legislation_roots("upstream-dispatch") { |_raw_root, _text_root| example.run }
      end

      it "routes fetch-bills on a Maryland run through Maryland discovery without contacting Legistar" do
        discovery_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter, discover: [])
        allow(Legislation::Adapters::GenericLegislationAdapter).to receive(:new).and_return(discovery_adapter)

        run = create(:legislation_pipeline_run,
          bill: nil,
          sway_locale: maryland,
          stages: %w[fetch-bills])

        expect { described_class.new.perform(run.id) }
          .to raise_error(StageError, /no bills were discovered for maryland-maryland-united_states/)

        expect(discovery_adapter).to have_received(:discover)
        expect(a_request(:any, /webapi\.legistar\.com/)).not_to have_been_made
      end

      it "routes fetch-law on a Congress run through CongressLawAdapter without checking Baltimore charter corpus" do
        corpus = instance_double(Legislation::CongressLawCorpusService)
        allow(Legislation::CongressLawCorpusService).to receive(:new)
          .with(law_root: Legislation::Paths.law(sway_locale: congress)).and_return(corpus)
        allow(corpus).to receive(:call).and_raise(StageError, "fetch_law: US Code download returned HTTP 503")
        run = create(:legislation_pipeline_run,
          bill: nil,
          sway_locale: congress,
          stages: %w[fetch-law])

        expect { described_class.new.perform(run.id) }
          .to raise_error(StageError, /US Code download returned HTTP 503/)
        expect(corpus).to have_received(:call)
        expect(File.exist?(Legislation::Paths.law(sway_locale: baltimore).join("charter.xml"))).to be(false)
      end
    end
  end

  describe "#find_pipeline_run" do
    subject(:job) { described_class.new }

    it "returns nil when pipeline_run_id does not exist in the database" do
      expect(job.send(:find_pipeline_run, -1)).to be_nil
    end

    it "returns nil when the pipeline run is already in a terminal state" do
      LegislationPipelineRun::TERMINAL_STATUSES.each do |status|
        terminal_run = create(:legislation_pipeline_run, status: status.to_s)
        expect(job.send(:find_pipeline_run, terminal_run.id)).to be_nil
      end
    end

    it "returns the run record when the pipeline run is non-terminal" do
      queued_run = create(:legislation_pipeline_run, status: "queued")
      expect(job.send(:find_pipeline_run, queued_run.id)).to eq(queued_run)
    end
  end

  describe "#prepare_pipeline_run!" do
    subject(:job) { described_class.new }

    it "tracks origin, transitions a queued run to running, and pre-seeds a single-bill run" do
      bill = create(:bill, external_id: "PREP-SINGLE-1", sway_locale: sway_locale)
      queued_run = create(:legislation_pipeline_run, bill: bill, status: "queued")

      result = job.send(:prepare_pipeline_run!, queued_run, origin: "fresh")

      expect(result).to be(true)
      expect(job.instance_variable_get(:@origin)).to eq("fresh")
      expect(queued_run.reload.status).to eq("running")
      expect(queued_run.pipeline_run_bills.pluck(:bill_external_id)).to contain_exactly("PREP-SINGLE-1")
    end

    it "hydrates all-bills runs without fetch-bills from disk" do
      all_bills_run = create(:legislation_pipeline_run, bill: nil, stages: ["extract-text"], status: "queued")
      seeder = instance_double(FetchBillsService, seed_from_disk: 1)
      allow(FetchBillsService).to receive(:new).with(run: all_bills_run).and_return(seeder)

      result = job.send(:prepare_pipeline_run!, all_bills_run)

      expect(result).to be(true)
      expect(seeder).to have_received(:seed_from_disk)
    end

    it "warns on unknown origin but still proceeds and returns true" do
      queued_run = create(:legislation_pipeline_run, status: "queued")
      expect(SwayLogging).to receive(:warn).with(
        "run_legislation_pipeline.unknown_origin",
        hash_including(run_id: queued_run.id, origin: "unknown-origin")
      )

      result = job.send(:prepare_pipeline_run!, queued_run, origin: "unknown-origin")

      expect(result).to be(true)
      expect(queued_run.reload.status).to eq("running")
    end

    it "returns false and leaves run awaiting summary batch when resume is deferred" do
      deferred_run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: 1.hour.from_now)

      result = job.send(:prepare_pipeline_run!, deferred_run, origin: "resume")

      expect(result).to be(false)
      expect(deferred_run.reload.status).to eq("awaiting_summary_batch")
    end

    it "normalizes stuck stage and transitions to running on resume when summary batch is not awaited" do
      stuck_run = create(:legislation_pipeline_run, status: "fetching_law")
      create(:pipeline_run_stage, legislation_pipeline_run: stuck_run, stage_name: "fetch_law", status: "running")

      result = job.send(:prepare_pipeline_run!, stuck_run, origin: "resume")

      expect(result).to be(true)
      expect(stuck_run.reload.status).to eq("running")
      expect(stuck_run.pipeline_run_stages.find_by(stage_name: "fetch_law").status).to eq("pending")
    end
  end

  describe "#finalize_pipeline_run!" do
    let(:job) { described_class.new }

    it "returns early without finalizing when run status is awaiting_summary_batch" do
      run = create(:legislation_pipeline_run, status: "awaiting_summary_batch")
      expect(job).not_to receive(:finalize_run_terminal_state)

      job.send(:finalize_pipeline_run!, run)

      expect(run.reload.status).to eq("awaiting_summary_batch")
    end

    it "finalizes a running run to succeeded when all bills succeeded" do
      run = create(:legislation_pipeline_run, status: "queued")
      run.start_running!

      job.send(:finalize_pipeline_run!, run)

      expect(run.reload.status).to eq("succeeded")
      expect(run.completed_at).to be_present
    end

    it "finalizes a running run to partial when a bill has failed stage_results" do
      run = create(:legislation_pipeline_run, status: "queued")
      run.start_running!
      create(:pipeline_run_bill, legislation_pipeline_run: run,
        stage_results: {"summarize" => {"status" => "failed", "at" => Time.current.iso8601}})

      job.send(:finalize_pipeline_run!, run)

      expect(run.reload.status).to eq("partial")
      expect(run.completed_at).to be_present
    end

    it "force-fails a run left stuck in a non-terminal stage status" do
      run = create(:legislation_pipeline_run, status: "queued")
      run.update_columns(status: "summarizing")
      allow(SwayLogging).to receive(:error)

      job.send(:finalize_pipeline_run!, run)

      expect(run.reload.status).to eq("failed")
      expect(run.completed_at).to be_present
      expect(run.error_message).to include("non_terminal_at_finalize")
    end
  end

  describe "#handle_run_failure" do
    let(:job) { described_class.new }

    it "returns nil safely without raising when run is nil" do
      expect { job.send(:handle_run_failure, nil, StandardError.new("boom")) }.not_to raise_error
    end

    it "records truncated error message, marks run as failed, and stamps completed_at" do
      run = create(:legislation_pipeline_run, status: "queued")
      run.start_running!

      long_error = "x" * 600
      job.send(:handle_run_failure, run, StandardError.new(long_error))

      run.reload
      expect(run.status).to eq("failed")
      expect(run.completed_at).to be_present
      expect(run.error_message.length).to eq(500)
    end

    it "does not attempt transition when run is already terminal" do
      run = create(:legislation_pipeline_run, status: "cancelled")
      allow(SwayLogging).to receive(:warn)

      job.send(:handle_run_failure, run, StandardError.new("error after cancel"))

      expect(run.reload.status).to eq("cancelled")
      expect(SwayLogging).to have_received(:warn).with(
        include("already in terminal state")
      )
    end
  end

  describe "#execute_stage!" do
    let(:job) { described_class.new }
    let(:run) { create(:legislation_pipeline_run, status: "running") }

    it "executes a RUN_LEVEL stage, transitions through start and complete, and returns false" do
      stub_bills = instance_double(FetchBillsService, call: [])
      allow(FetchBillsService).to receive(:new).with(run: run, mode: :discover).and_return(stub_bills)

      expect(run).to receive(:start_fetch_bills!).and_call_original
      expect(run).to receive(:complete_fetch_bills!).and_call_original

      result = job.send(:execute_stage!, run, :fetch_bills, auto_included: false)

      expect(result).to be(false)
      expect(run.reload.status).to eq("running")
      expect(stub_bills).to have_received(:call)
    end

    it "executes a BILL_LEVEL stage, transitions through start and complete, and returns false" do
      allow(job).to receive(:run_bill_level_stage).with(run, :parse_sections, auto_included: false).and_return(nil)

      expect(run).to receive(:start_parse_sections!).and_call_original
      expect(run).to receive(:complete_parse_sections!).and_call_original

      result = job.send(:execute_stage!, run, :parse_sections, auto_included: false)

      expect(result).to be(false)
      expect(run.reload.status).to eq("running")
    end

    it "transitions to awaiting_summary_batch and returns true when a bill-level stage enters batch mode" do
      allow(job).to receive(:run_bill_level_stage)
        .with(run, :summarize, auto_included: false)
        .and_return(described_class::AWAITING_SUMMARY_BATCH)

      expect(run).to receive(:start_summarize!).and_call_original
      expect(run).to receive(:await_summary_batch!).and_call_original
      expect(run).not_to receive(:complete_summarize!)

      result = job.send(:execute_stage!, run, :summarize, auto_included: false)

      expect(result).to be(true)
      expect(run.reload.status).to eq("awaiting_summary_batch")
    end

    it "raises StageError when stage is not classified in RUN_LEVEL_STAGES or BILL_LEVEL_STAGES" do
      expect {
        job.send(:execute_stage!, run, :nonexistent_stage)
      }.to raise_error(StageError, "stage nonexistent_stage is not classified as RUN_LEVEL or BILL_LEVEL")
    end

    it "rescues StateMachines::InvalidTransition, logs a warning, and re-raises as StageError" do
      allow(run).to receive(:start_fetch_bills!).and_raise(
        StateMachines::InvalidTransition.new(run, run.class.state_machine(:status), :start_fetch_bills)
      )
      expect(SwayLogging).to receive(:warn).with(
        "run_legislation_pipeline.invalid_transition",
        hash_including(run_id: run.id, stage: :fetch_bills)
      )

      expect {
        job.send(:execute_stage!, run, :fetch_bills)
      }.to raise_error(StageError, /stage fetch_bills invalid state transition:/)
    end

    it "manages Pipeline::Current.current_auto_include_context lifecycle and guarantees clearing in ensure on failure" do
      allow(job).to receive(:bills_triggering_auto_include).and_return(["AUTO-1"])
      allow(FetchBillsService).to receive(:new).and_raise(StandardError, "forced stage failure")

      expect {
        job.send(:execute_stage!, run, :fetch_bills, auto_included: true)
      }.to raise_error(StageError, /forced stage failure/)

      expect(Pipeline::Current.current_auto_include_context).to be_nil
    end

    it "configures :backfill_missing when auto_included is true and :discover when false for :fetch_bills" do
      expect(job.send(:run_level_service_kwargs, run, :fetch_bills, auto_included: true))
        .to eq({run: run, mode: :backfill_missing})
      expect(job.send(:run_level_service_kwargs, run, :fetch_bills, auto_included: false))
        .to eq({run: run, mode: :discover})
    end
  end
end
