# == Schema Information
#
# Table name: legislation_pipeline_runs
# Database name: primary
#
#  id                      :integer          not null, primary key
#  completed_at            :datetime
#  current_stage           :string
#  download_missing_assets :boolean          default(TRUE), not null
#  error_message           :text
#  idempotency_key         :string           not null
#  origin                  :string           default("fresh"), not null
#  stages                  :text
#  started_at              :datetime
#  status                  :string           default("queued"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  bill_id                 :integer
#  parent_run_id           :string
#  remote_run_id           :string
#  sway_locale_id          :integer
#
# Indexes
#
#  index_legislation_pipeline_runs_on_bill_id          (bill_id)
#  index_legislation_pipeline_runs_on_idempotency_key  (idempotency_key) UNIQUE
#  index_legislation_pipeline_runs_on_parent_run_id    (parent_run_id)
#  index_legislation_pipeline_runs_on_remote_run_id    (remote_run_id) UNIQUE WHERE remote_run_id IS NOT NULL
#  index_legislation_pipeline_runs_on_status           (status)
#  index_legislation_pipeline_runs_on_sway_locale_id   (sway_locale_id)
#
# Foreign Keys
#
#  bill_id         (bill_id => bills.id)
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
require "rails_helper"

# Defined outside the describe block: a constant assigned inside a block lands on
# Object anyway, which rubocop's Lint/ConstantDefinitionInBlock points out, so
# putting it at the top level says so plainly.
STAGES_52_03 = %i[fetch_bills extract_text parse_sections generate_diffs fetch_law fetch_hearings summarize].freeze

RSpec.describe LegislationPipelineRun, type: :model do
  # remote_run_id used to be filled in by a webhook from a separate Python
  # service. That service is gone and nothing else writes the column, so the
  # row's own before_validation hook has to fill it in.
  describe "remote_run_id assignment" do
    it "auto-assigns a UUID on create when remote_run_id is not provided" do
      run = described_class.create!(stages: ["fetch-bills"])
      expect(run.remote_run_id).to be_present
      expect(run.remote_run_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "preserves an externally-supplied remote_run_id (find_or_initialize_by webhook path)" do
      run = described_class.create!(remote_run_id: "supplied-id", stages: ["fetch-bills"])
      expect(run.remote_run_id).to eq("supplied-id")
    end

    it "generates distinct UUIDs across rows" do
      run_a = described_class.create!(stages: ["fetch-bills"])
      run_b = described_class.create!(stages: ["fetch-bills"])
      expect(run_a.remote_run_id).not_to eq(run_b.remote_run_id)
    end
  end

  # @lat: [[legislation-pipeline-run-current-stage#What it does not answer]]
  describe "stage tracking via state-machine transitions" do
    let(:run) do
      described_class.create!(stages: ["fetch-bills", "extract-text"]).tap(&:start_running!)
    end

    it "sets current_stage to the DAG name when transitioning into a stage state" do
      expect { run.start_fetch_bills! }.to change { run.reload.current_stage }.from(nil).to("fetch_bills")
    end

    it "preserves current_stage when transitioning out of a stage back to running" do
      run.start_fetch_bills!
      expect { run.complete_fetch_bills! }.not_to change { run.reload.current_stage }
      expect(run.reload.current_stage).to eq("fetch_bills")
    end

    it "overwrites current_stage when entering a different stage" do
      run.start_fetch_bills!
      run.complete_fetch_bills!
      expect { run.start_extract_text! }.to change { run.reload.current_stage }.from("fetch_bills").to("extract_text")
    end

    it "creates a PipelineRunStage row with status=running on entry" do
      expect { run.start_fetch_bills! }.to change { run.pipeline_run_stages.count }.by(1)
      stage = run.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      expect(stage.status).to eq("running")
      expect(stage.started_at).to be_present
      expect(stage.finished_at).to be_nil
    end

    it "marks the PipelineRunStage row succeeded on complete_X! transition" do
      run.start_fetch_bills!
      run.complete_fetch_bills!
      stage = run.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      expect(stage.status).to eq("succeeded")
      expect(stage.finished_at).to be_present
    end

    it "marks the PipelineRunStage row failed when the run is force-failed from a stage state" do
      run.start_fetch_bills!
      run.force_fail!
      stage = run.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      expect(stage.status).to eq("failed")
      expect(stage.finished_at).to be_present
    end

    # @lat: [[legislation-pipeline-mark-cancelled-stage-sync#Why cancelling from the plain :running state must not create or touch any stage row]]
    it "marks the PipelineRunStage row failed when the run is cancelled from a stage state (WR-01)" do
      run.start_fetch_bills!
      run.mark_cancelled!
      stage = run.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      expect(stage.status).to eq("failed")
      expect(stage.finished_at).to be_present
    end

    # @lat: [[legislation-pipeline-mark-cancelled-stage-sync#Why a stage that already succeeded must not be touched by a later cancel]]
    it "does NOT touch a succeeded stage row when the run cancels mid-DAG (WR-NEW-03)" do
      run.start_fetch_bills!
      run.complete_fetch_bills!
      run.start_fetch_law!
      run.mark_cancelled!
      fetch_bills_stage = run.pipeline_run_stages.find_by(stage_name: "fetch_bills")
      fetch_law_stage = run.pipeline_run_stages.find_by(stage_name: "fetch_law")
      expect(fetch_bills_stage.status).to eq("succeeded") # left alone
      expect(fetch_bills_stage.finished_at).to be_present
      expect(fetch_law_stage.status).to eq("failed") # the cancel-a-stage path fired
      expect(fetch_law_stage.finished_at).to be_present
    end

    # @lat: [[legislation-pipeline-mark-cancelled-stage-sync#Why cancelling from the plain :running state must not create or touch any stage row]]
    it "does NOT touch any stage row when the run cancels from :running (WR-NEW-03)" do
      expect(run.status).to eq("running")
      run.mark_cancelled!
      expect(run.pipeline_run_stages.count).to eq(0)
    end

    it "idempotently re-uses the existing PipelineRunStage row on resume re-entry" do
      run.start_fetch_bills!
      # Pretend a worker was killed mid-stage: the stage row is already there,
      # and the run's status is put back by hand.
      run.update_columns(status: "running")
      expect { run.start_fetch_bills! }.not_to change { run.pipeline_run_stages.count }
      expect(run.pipeline_run_stages.find_by(stage_name: "fetch_bills").status).to eq("running")
    end
  end

  describe "state machine" do
    let(:run) { described_class.create!(remote_run_id: "abc", stages: ["fetch-bills"]) }

    it "starts in queued state" do
      expect(run.status).to eq("queued")
    end

    it "transitions queued -> running -> completed" do
      expect { run.start_running! }.to change { run.status }.from("queued").to("running")
      expect { run.mark_completed! }.to change { run.status }.from("running").to("completed")
    end

    it "transitions running -> failed with error_message" do
      run.start_running!
      run.update!(error_message: "boom")
      expect { run.mark_failed! }.to change { run.status }.from("running").to("failed")
      expect(run.error_message).to eq("boom")
    end

    it "serializes stages as JSON array" do
      run.update!(stages: ["fetch-bills", "extract-text"])
      expect(run.reload.stages).to eq(["fetch-bills", "extract-text"])
    end

    it "transitions queued -> cancelled" do
      expect { run.mark_cancelled! }.to change { run.status }.from("queued").to("cancelled")
    end

    it "transitions running -> cancelled" do
      run.start_running!
      expect { run.mark_cancelled! }.to change { run.status }.from("running").to("cancelled")
    end

    it "cancels a run stuck in a per-stage state after a dead worker" do
      run.start_running!
      run.start_fetch_hearings!
      expect(run.status).to eq("fetching_hearings")
      expect { run.mark_cancelled! }.to change { run.status }.to("cancelled")
    end
  end

  describe "pipeline associations" do
    it "has_many :pipeline_run_bills" do
      run = create(:legislation_pipeline_run)
      bill = create(:pipeline_run_bill, legislation_pipeline_run: run)
      expect(run.pipeline_run_bills).to include(bill)
    end

    it "has_many :pipeline_run_stages" do
      run = create(:legislation_pipeline_run)
      stage = create(:pipeline_run_stage, legislation_pipeline_run: run)
      expect(run.pipeline_run_stages).to include(stage)
    end

    it "destroys child rows when parent is destroyed (dependent: :destroy)" do
      run = create(:legislation_pipeline_run)
      create(:pipeline_run_bill, legislation_pipeline_run: run)
      create(:pipeline_run_stage, legislation_pipeline_run: run)
      expect { run.destroy }.to change(PipelineRunBill, :count).by(-1)
        .and change(PipelineRunStage, :count).by(-1)
    end

    it "supports legacy runs with no children" do
      legacy_run = create(:legislation_pipeline_run)
      expect(legacy_run.pipeline_run_bills).to eq([])
      expect(legacy_run.pipeline_run_stages).to eq([])
    end
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#One walk decides the per-bill order]]
  describe "#each_pipeline_run_bill" do
    it "yields the bills in the order the per-bill grid shows, not insertion order" do
      run = create(:legislation_pipeline_run)
      # Inserted back to front on purpose: with the order dropped, SQLite hands
      # these back by rowid and the example reads them 3, 1, 2.
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "C-003", sort_order: 3)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "A-001", sort_order: 1)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "B-002", sort_order: 2)

      yielded = []
      run.each_pipeline_run_bill { |bill_run| yielded << bill_run.bill_external_id }

      expect(yielded).to eq(%w[A-001 B-002 C-003])
    end

    # ActiveRecord writes this through the MODEL's logger, not Rails.logger, so
    # that is the seam to watch.
    it "logs no 'scoped order is ignored' warning" do
      run = create(:legislation_pipeline_run)
      create(:pipeline_run_bill, legislation_pipeline_run: run, sort_order: 1)

      warnings = []
      logger = PipelineRunBill.logger
      allow(PipelineRunBill).to receive(:logger).and_return(logger)
      allow(logger).to receive(:warn) { |message| warnings << message.to_s }

      run.each_pipeline_run_bill { |_bill_run| nil }

      expect(warnings.grep(/Scoped order is ignored/)).to be_empty
    end
  end

  describe "#to_builder" do
    it "returns Jbuilder with id, status, current_stage, error_message, bill_id, bill_external_id, started_at, completed_at" do
      bill = create(:bill, external_id: "24-0001")
      run = described_class.create!(remote_run_id: "abc", stages: ["fetch-bills"], status: "running", current_stage: "extract-text", bill: bill)
      props = JSON.parse(run.to_builder.target!)
      expect(props).to include("id", "status", "current_stage", "error_message", "bill_id", "bill_external_id", "started_at", "completed_at")
      # @lat: [[resume-stage-history-walk#It reads the runs before this one, never this one]]
      expect(props).not_to include("bill_count", "summary")
      expect(props["bill_id"]).to eq(bill.id)
      expect(props["bill_external_id"]).to eq("24-0001")
    end

    # @lat: [[legislation-pipeline-external-id-ambiguity#LegislationPipelineRun.to_builder's title lookup]]
    it "omits the title of an external_id that two locales share (A1-WR-03)" do
      create(:bill, external_id: "GRID-DUP", title: "Baltimore ordinance", scheduled_release_date_utc: 400.days.ago)
      create(:bill, external_id: "GRID-DUP", title: "A federal bill", sway_locale: create(:sway_locale), scheduled_release_date_utc: 401.days.ago)
      create(:bill, external_id: "GRID-OK", title: "Unambiguous", scheduled_release_date_utc: 402.days.ago)
      run = create(:legislation_pipeline_run, bill: nil)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "GRID-DUP", sort_order: 0)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "GRID-OK", sort_order: 1)

      rows = JSON.parse(run.to_builder.target!).fetch("pipeline_run_bills")
      titles = rows.to_h { |row| [row["bill_external_id"], row["title"]] }

      expect(titles["GRID-OK"]).to eq("Unambiguous")
      expect(titles["GRID-DUP"]).to be_nil
    end
  end

  # Covers the parent_run association, the partial/succeeded state-machine
  # events, and JSON serialization of the summary column. These pieces exist
  # here first; the service and controller code that actually uses them is
  # wired up separately.
  describe "parent_run association" do
    it "exposes parent_run when parent_run_id is set to another run's id" do
      parent = create(:legislation_pipeline_run, status: "failed")
      child = create(:legislation_pipeline_run, parent_run_id: parent.id.to_s)
      expect(child.parent_run).to eq(parent)
    end

    it "exposes child_runs collection from parent perspective" do
      parent = create(:legislation_pipeline_run, status: "failed")
      child_a = create(:legislation_pipeline_run, parent_run_id: parent.id.to_s, origin: "resume")
      child_b = create(:legislation_pipeline_run, parent_run_id: parent.id.to_s, origin: "restart")
      expect(parent.child_runs).to contain_exactly(child_a, child_b)
    end

    it "nullifies child_runs.parent_run_id when parent is destroyed (dependent: :nullify)" do
      parent = create(:legislation_pipeline_run, status: "failed")
      child = create(:legislation_pipeline_run, parent_run_id: parent.id.to_s, origin: "resume")
      parent.destroy
      expect(child.reload.parent_run_id).to be_nil
    end

    it "leaves parent_run nil for fresh runs (no parent linkage)" do
      run = create(:legislation_pipeline_run)
      expect(run.parent_run).to be_nil
      expect(run.parent_run_id).to be_nil
      expect(run.origin).to eq("fresh")
    end
  end

  # @lat: [[legislation-pipeline-run-current-stage#Why completed_at is stamped in the same hook]]
  describe "completed_at stamped on terminal transitions" do
    # Two hand-written lists that are meant to be opposites are the fault
    # this phase keeps finding: add a status to neither and it falls in the
    # gap, here meaning a finished run that never gets a finish time. This
    # example fails the moment a status belongs to both lists or to neither.
    it "splits every status into exactly one of finished or not finished" do
      every_status = described_class.state_machine(:status).states.map(&:name).compact

      expect(described_class::TERMINAL_STATUSES & described_class::PHASE_52_NON_TERMINAL_STATES).to be_empty
      expect((described_class::TERMINAL_STATUSES + described_class::PHASE_52_NON_TERMINAL_STATES).sort)
        .to eq(every_status.sort)
    end

    it "stamps completed_at on mark_succeeded!" do
      run = create(:legislation_pipeline_run, :running)
      expect(run.completed_at).to be_nil
      expect { run.mark_succeeded! }.to change { run.reload.completed_at }.from(nil)
    end

    it "stamps completed_at on mark_partial!" do
      run = create(:legislation_pipeline_run, :running)
      expect { run.mark_partial! }.to change { run.reload.completed_at }.from(nil)
    end

    it "stamps completed_at on mark_failed! from running" do
      run = create(:legislation_pipeline_run, :running)
      expect { run.mark_failed! }.to change { run.reload.completed_at }.from(nil)
    end

    it "stamps completed_at on mark_failed! from queued" do
      run = create(:legislation_pipeline_run)
      expect { run.mark_failed! }.to change { run.reload.completed_at }.from(nil)
    end

    it "stamps completed_at on mark_cancelled!" do
      run = create(:legislation_pipeline_run, :running)
      expect { run.mark_cancelled! }.to change { run.reload.completed_at }.from(nil)
    end

    it "stamps completed_at on force_fail!" do
      run = create(:legislation_pipeline_run, :running)
      expect { run.force_fail! }.to change { run.reload.completed_at }.from(nil)
    end

    it "stamps completed_at on mark_completed! (legacy event, older rows)" do
      run = create(:legislation_pipeline_run, :running)
      expect { run.mark_completed! }.to change { run.reload.completed_at }.from(nil)
    end
  end

  describe "state machine — partial / succeeded" do
    it "transitions running -> succeeded via mark_succeeded!" do
      run = create(:legislation_pipeline_run, :running)
      expect { run.mark_succeeded! }.to change { run.status }.from("running").to("succeeded")
      expect(run.succeeded?).to be(true)
    end

    it "transitions running -> partial via mark_partial!" do
      run = create(:legislation_pipeline_run, :running)
      expect { run.mark_partial! }.to change { run.status }.from("running").to("partial")
      expect(run.partial?).to be(true)
    end

    it "does NOT transition queued -> succeeded (mark_succeeded only fires from running)" do
      run = create(:legislation_pipeline_run)
      expect(run.can_mark_succeeded?).to be(false)
    end

    it "does NOT transition queued -> partial (mark_partial only fires from running)" do
      run = create(:legislation_pipeline_run)
      expect(run.can_mark_partial?).to be(false)
    end
  end

  # @lat: [[resume-stage-history-walk#It reads the runs before this one, never this one]]
  describe "to_builder run-outcome fields" do
    it "surfaces parent_run_id, origin, kind, pipeline_run_stages keys" do
      parent = create(:legislation_pipeline_run, status: "failed")
      bill = create(:bill, external_id: "B-100")
      run = create(:legislation_pipeline_run, parent_run_id: parent.id.to_s, origin: "resume", bill: bill)
      props = JSON.parse(run.to_builder.target!)
      expect(props).to include("parent_run_id", "origin", "kind", "pipeline_run_stages")
      expect(props["parent_run_id"]).to eq(parent.id.to_s)
      expect(props["origin"]).to eq("resume")
      expect(props["kind"]).to eq("single") # bill_id present -> single
      expect(props["pipeline_run_stages"]).to eq([])
    end

    it "derives kind='all_bills' when bill_id is nil" do
      run = create(:legislation_pipeline_run)
      props = JSON.parse(run.to_builder.target!)
      expect(props["kind"]).to eq("all_bills")
    end
  end

  # @lat: [[legislation-pipeline-run-stage-timing-wire-shape#pipeline-run-stage-timing]]
  describe "to_builder pipeline_run_stages timing" do
    it "serializes a stage row's exact key set, including its start and finish time" do
      run = described_class.create!(stages: ["fetch-bills"]).tap(&:start_running!)
      run.start_fetch_bills!
      run.complete_fetch_bills!
      stage = run.pipeline_run_stages.find_by(stage_name: "fetch_bills")

      row = JSON.parse(run.to_builder.target!).fetch("pipeline_run_stages").first

      expect(row.keys).to contain_exactly("stage_name", "status", "position", "output_summary", "started_at", "finished_at")
      # Exact strings, not a parse: the whole point is that these carry the same UTC
      # second-precision representation as the recent-runs row.
      expect(row["started_at"]).to eq(stage.started_at.utc.iso8601)
      expect(row["finished_at"]).to eq(stage.finished_at.utc.iso8601)
    end

    it "serializes a null finished_at for a stage that has started but not finished" do
      run = described_class.create!(stages: ["fetch-bills"]).tap(&:start_running!)
      run.start_fetch_bills!

      row = JSON.parse(run.to_builder.target!).fetch("pipeline_run_stages").first

      expect(row["started_at"]).to be_present
      expect(row["finished_at"]).to be_nil
    end

    it "serializes an empty stage list, inventing no stage time, for a run that failed before any stage started" do
      run = described_class.create!(stages: ["fetch-bills"]).tap(&:start_running!)
      run.force_fail!

      props = JSON.parse(run.to_builder.target!)

      expect(props["pipeline_run_stages"]).to eq([])
    end

    # Sub-second components are deliberate: a raw ActiveSupport::TimeWithZone
    # serializes at millisecond precision, so only a timestamp carrying one can
    # tell the two representations apart.
    it "serializes the run-level start and finish time in the same representation as the stage rows" do
      run = create(:legislation_pipeline_run, :failed,
        started_at: Time.utc(2026, 8, 27, 20, 19, 11, 123_000),
        completed_at: Time.utc(2026, 8, 27, 20, 21, 47, 456_000))

      props = JSON.parse(run.to_builder.target!)

      expect(props["started_at"]).to eq("2026-08-27T20:19:11Z")
      expect(props["completed_at"]).to eq("2026-08-27T20:21:47Z")
    end

    it "serializes a pipeline_run_bills row's start and finish time in that same representation" do
      run = create(:legislation_pipeline_run)
      create(:pipeline_run_bill, :succeeded,
        legislation_pipeline_run: run,
        bill_external_id: "HB-TIMING-1",
        started_at: Time.utc(2026, 8, 27, 20, 19, 11, 123_000),
        finished_at: Time.utc(2026, 8, 27, 20, 21, 47, 456_000))

      row = JSON.parse(run.to_builder.target!).fetch("pipeline_run_bills").first

      expect(row["started_at"]).to eq("2026-08-27T20:19:11Z")
      expect(row["finished_at"]).to eq("2026-08-27T20:21:47Z")
    end

    it "serializes a null start and finish time for a pipeline_run_bills row that has not begun" do
      run = create(:legislation_pipeline_run)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "HB-TIMING-2")

      row = JSON.parse(run.to_builder.target!).fetch("pipeline_run_bills").first

      expect(row["started_at"]).to be_nil
      expect(row["finished_at"]).to be_nil
    end
  end

  # @lat: [[run-pipeline-request-contract#POST /bills/run_pipeline request contract]]
  describe "to_builder emits download_missing_assets and no longer emits refresh" do
    it "surfaces download_missing_assets but NOT refresh in the JSON output" do
      run = create(:legislation_pipeline_run)
      props = JSON.parse(run.to_builder.target!)
      expect(props).to have_key("download_missing_assets")
      expect(props).not_to have_key("refresh")
    end

    it "round-trips download_missing_assets=false through create+to_builder" do
      run = create(:legislation_pipeline_run, download_missing_assets: false)
      props = JSON.parse(run.to_builder.target!)
      expect(props["download_missing_assets"]).to be(false)
    end

    it "defaults download_missing_assets=true on bare create" do
      run = LegislationPipelineRun.create!(stages: ["fetch-bills"])
      expect(run.download_missing_assets).to be(true)
      props = JSON.parse(run.to_builder.target!)
      expect(props["download_missing_assets"]).to be(true)
    end
  end

  # Tests for the idempotency_key column and the before_create callback that
  # fills it in.
  describe "idempotency_key" do
    it "stamps idempotency_key with a UUID before_create" do
      run = LegislationPipelineRun.create!(stages: ["fetch-bills"])
      expect(run.idempotency_key).to match(/\A[0-9a-f-]{36}\z/)
      expect(run.idempotency_key).not_to be_blank
    end

    it "rejects duplicate idempotency_key at the DB layer" do
      key = SecureRandom.uuid
      LegislationPipelineRun.create!(stages: ["fetch-bills"], idempotency_key: key)
      expect {
        LegislationPipelineRun.create!(stages: ["fetch-bills"], idempotency_key: key)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "preserves idempotency_key across reload (column is NOT NULL)" do
      run = LegislationPipelineRun.create!(stages: ["fetch-bills"])
      original_key = run.idempotency_key
      expect(original_key).not_to be_nil
      expect(run.reload.idempotency_key).to eq(original_key)
    end
  end

  # Tests that to_builder outputs a pipeline_run_bills array for all-bills runs.
  describe "to_builder pipeline_run_bills" do
    it "omits pipeline_run_bills key when bill_id is present (single-bill run, kind=single)" do
      bill = create(:bill, external_id: "HB-50-A")
      run = create(:legislation_pipeline_run, bill: bill)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "HB-50-A")

      props = JSON.parse(run.to_builder.target!)
      # Jbuilder writes a nil as null, so check the value is either null or
      # missing. Either way the React grid draws nothing.
      expect(props["pipeline_run_bills"]).to be_nil
    end

    it "emits an array of per-bill rows when bill_id is blank (all-bills run, kind=all_bills)" do
      bill_a = create(:bill, external_id: "HB-50-A", title: "Bill A")
      bill_b = create(:bill, external_id: "HB-50-B", title: "Bill B")
      bill_c = create(:bill, external_id: "HB-50-C", title: "Bill C")

      run = create(:legislation_pipeline_run)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_a.external_id, status: "running", sort_order: 1)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_b.external_id, status: "succeeded", sort_order: 2)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_c.external_id, status: "pending", sort_order: 3)

      props = JSON.parse(run.to_builder.target!)
      rows = props["pipeline_run_bills"]
      expect(rows).to be_an(Array)
      expect(rows.length).to eq(3)

      first = rows[0]
      expect(first).to include("bill_external_id", "title", "status", "started_at", "finished_at", "error_message", "sort_order")
    end

    it "truncates row title to 80 characters" do
      run = create(:legislation_pipeline_run)
      long_title = "x" * 200
      bill = create(:bill, external_id: "HB-50-LONG", title: long_title)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)

      props = JSON.parse(run.to_builder.target!)
      row = props["pipeline_run_bills"].first
      expect(row["title"].length).to be <= 80
    end

    # @lat: [[pipeline-run-bill-lifecycle#Why LegislationPipelineRun's pipeline_run_bills association orders by sort_order]]
    it "emits pipeline_run_bills in sort_order ASC (bill.id ASC contract)" do
      bill_a = create(:bill, external_id: "HB-50-ORD-A", title: "Bill A")
      bill_b = create(:bill, external_id: "HB-50-ORD-B", title: "Bill B")
      bill_c = create(:bill, external_id: "HB-50-ORD-C", title: "Bill C")
      run = create(:legislation_pipeline_run)
      # Insert the rows out of order on purpose. If the code just ordered by
      # the primary key instead of sort_order, this would catch it, because
      # the two orders would disagree.
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_c.external_id, sort_order: 3)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_a.external_id, sort_order: 1)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_b.external_id, sort_order: 2)

      props = JSON.parse(run.reload.to_builder.target!)
      rows = props["pipeline_run_bills"]
      expect(rows.pluck("sort_order")).to eq([1, 2, 3])
      expect(rows.pluck("bill_external_id")).to eq(
        [bill_a.external_id, bill_b.external_id, bill_c.external_id]
      )
    end

    it "resolves all titles via a single Bill.where(...).pluck(...) query (no N+1)" do
      bill_a = create(:bill, external_id: "HB-50-A", title: "Bill A")
      bill_b = create(:bill, external_id: "HB-50-B", title: "Bill B")
      bill_c = create(:bill, external_id: "HB-50-C", title: "Bill C")
      run = create(:legislation_pipeline_run)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_a.external_id, sort_order: 1)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_b.external_id, sort_order: 2)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_c.external_id, sort_order: 3)

      # Watch Bill.where: to_builder must call it exactly once to look up titles.
      call_count = 0
      original_where = Bill.method(:where)
      allow(Bill).to receive(:where) do |*args, **kwargs|
        call_count += 1
        original_where.call(*args, **kwargs)
      end

      run.reload.to_builder.target!
      expect(call_count).to eq(1)
    end
  end

  # @lat: [[legislation-pipeline-stage-list-naming-and-order#The class-load check tying PHASE_52_STAGE_STATES to STAGE_STATUS_TO_DAG_NAME]]
  describe "STAGE_STATUS_TO_DAG_NAME class-load integrity check (CG6-04 / HI3-01)" do
    it "has a STAGE_STATUS_TO_DAG_NAME entry for every PHASE_52_STAGE_STATES symbol" do
      missing = described_class::PHASE_52_STAGE_STATES.reject do |state|
        described_class::STAGE_STATUS_TO_DAG_NAME.key?(state.to_s)
      end
      expect(missing).to be_empty,
        "expected every PHASE_52_STAGE_STATES symbol to map to a DAG stage name; missing: #{missing.inspect}"
    end

    it "the integrity-check logic raises when a PHASE_52_STAGE_STATES symbol has no mapping (drift guard)" do
      # Pretend somebody added a state without its matching entry. The check at
      # model lines 148-155 is this same loop, run here against an altered copy,
      # to show the check itself is correct and would fire if the two lists ever
      # drifted apart.
      mutated_states = described_class::PHASE_52_STAGE_STATES + [:fictitious_stage]

      expect {
        mutated_states.each do |state|
          unless described_class::STAGE_STATUS_TO_DAG_NAME.key?(state.to_s)
            raise "LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME missing entry for #{state.inspect}"
          end
        end
      }.to raise_error(RuntimeError, /missing entry for :fictitious_stage/)
    end

    it "exposes both constants as frozen (drift can't be silently patched at runtime)" do
      expect(described_class::PHASE_52_STAGE_STATES).to be_frozen
      expect(described_class::STAGE_STATUS_TO_DAG_NAME).to be_frozen
    end
  end

  describe "stage events + force_fail" do
    before do
      allow(PipelineActivityLogger).to receive(:emit_state_transition!)
      allow(PipelineRunChannel).to receive(:broadcast_to)
    end

    STAGES_52_03.each do |stage|
      it "transitions running → #{stage}-ing via start_#{stage}!" do
        run = create(:legislation_pipeline_run, status: "running")
        running_state = stage.to_s.sub(/_(bills|text|sections|diffs|law|hearings)$/) { "ing_#{$1}" }
        running_state = "summarizing" if stage == :summarize
        running_state = "fetching_bills" if stage == :fetch_bills
        running_state = "extracting_text" if stage == :extract_text
        running_state = "parsing_sections" if stage == :parse_sections
        running_state = "generating_diffs" if stage == :generate_diffs
        running_state = "fetching_law" if stage == :fetch_law
        running_state = "fetching_hearings" if stage == :fetch_hearings

        expect { run.public_send(:"start_#{stage}!") }.to change(run, :status).from("running").to(running_state)
      end

      it "transitions #{stage}-ing → running via complete_#{stage}!" do
        run = create(:legislation_pipeline_run, status: "running")
        run.public_send(:"start_#{stage}!")
        expect { run.public_send(:"complete_#{stage}!") }.to change(run, :status).to("running")
      end
    end

    describe "#force_fail!" do
      it "transitions queued → failed" do
        run = create(:legislation_pipeline_run, status: "queued")
        expect { run.force_fail! }.to change(run, :status).from("queued").to("failed")
      end

      it "transitions running → failed" do
        run = create(:legislation_pipeline_run, status: "running")
        expect { run.force_fail! }.to change(run, :status).from("running").to("failed")
      end

      it "transitions summarizing → failed" do
        run = create(:legislation_pipeline_run, status: "running")
        run.start_summarize!
        expect { run.force_fail! }.to change(run, :status).from("summarizing").to("failed")
      end
    end
  end

  describe "audit-log (in-transition) + broadcast (after-commit) split" do
    before do
      allow(PipelineActivityLogger).to receive(:emit_state_transition!)
      allow(PipelineRunChannel).to receive(:broadcast_to)
    end

    it "emits exactly one emit_state_transition! call per transition" do
      run = create(:legislation_pipeline_run, status: "running")
      run.start_fetch_bills!
      expect(PipelineActivityLogger).to have_received(:emit_state_transition!).with(
        run: run, from: "running", to: "fetching_bills", event: :start_fetch_bills
      ).once
    end

    it "emits exactly one PipelineRunChannel broadcast per transition with scope: \"run\"" do
      run = create(:legislation_pipeline_run, status: "running", remote_run_id: "rid-001")
      run.start_fetch_bills!
      expect(PipelineRunChannel).to have_received(:broadcast_to).with(
        anything,
        hash_including(scope: "run", run_id: run.id, status: "fetching_bills")
      ).once
    end

    it "does NOT broadcast when update_columns writes a non-status column" do
      run = create(:legislation_pipeline_run, status: "running")
      run.update_columns(error_message: "non-status mutation")
      expect(PipelineRunChannel).not_to have_received(:broadcast_to)
    end

    it "rolls back the transition AND does NOT broadcast when emit_state_transition! raises" do
      run = create(:legislation_pipeline_run, status: "running")
      allow(PipelineActivityLogger).to receive(:emit_state_transition!).and_raise(StandardError, "boom")

      expect { run.start_fetch_bills! }.to raise_error(StandardError, "boom")
      expect(run.reload.status).to eq("running")
      expect(PipelineRunChannel).not_to have_received(:broadcast_to)
    end
  end

  # @lat: [[reclaim-abandoned-pipeline-runs-job-design#Why per-stage status is ever written directly, bypassing the state machine]]
  describe "#abandoned?" do
    # updated_at is written by every save, so a factory cannot set it. update_all
    # is the only way to produce the row this predicate is about: one nothing has
    # written to for hours.
    def quiet_run(status, quiet_for: described_class::ABANDONED_AFTER + 1.minute)
      run = create(:legislation_pipeline_run, status: status)
      described_class.where(id: run.id).update_all(updated_at: quiet_for.ago)
      run.reload
    end

    # Its table is absent in test and the lookup fails closed, so an unstubbed
    # example would silently test the attended case.
    def with_no_live_job
      allow(described_class).to receive(:solid_queue_job_exists_for?).and_return(false)
    end

    # `orphan?` looks at queued and running only, so the status the 477-hour run
    # sat in was invisible to it, as is every per-stage status.
    it "covers every non-final status, per-stage ones included" do
      with_no_live_job

      described_class::PHASE_52_NON_TERMINAL_STATES.each do |status|
        expect(quiet_run(status.to_s)).to be_abandoned, "#{status} was not recognised as abandoned"
      end
    end

    it "says nothing about a run that has already finished" do
      with_no_live_job

      %w[succeeded completed partial failed cancelled].each do |status|
        expect(quiet_run(status)).not_to be_abandoned, "#{status} is finished and cannot be abandoned"
      end
    end

    # A run inside a slow stage writes nothing here for an hour, so silence
    # without this check fails a run under its own worker.
    it "leaves a quiet run alone while a job is still carrying it" do
      allow(described_class).to receive(:solid_queue_job_exists_for?).and_return(true)

      expect(quiet_run("summarizing")).not_to be_abandoned
    end

    it "leaves a run alone while something is still writing to it" do
      with_no_live_job

      expect(quiet_run("summarizing", quiet_for: 1.minute)).not_to be_abandoned
    end

    # Under-claiming is the safe direction: the cost of a wrong "attended" is an
    # operator waiting, and the cost of a wrong "abandoned" is failing a run that
    # a worker is still spending money on.
    it "calls a run attended when the queue database cannot be read" do
      # Unstubbed on purpose: solid_queue_jobs has no table in test, so the real
      # lookup raises here exactly as a broken queue database would.
      allow(SwayLogging).to receive(:warn)

      expect(quiet_run("summarizing")).not_to be_abandoned
    end

    # The scope is the sweep's first pass and must not be narrower than the
    # predicate, or a row it cannot see is a row nothing ever closes.
    it "offers the same rows as candidates that the predicate would call abandoned" do
      quiet = quiet_run("summarizing")
      busy = quiet_run("summarizing", quiet_for: 1.minute)
      done = quiet_run("succeeded")

      candidates = described_class.abandoned_candidates.to_a

      expect(candidates).to include(quiet)
      expect(candidates).not_to include(busy, done)
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#Why no job waits on a batch]]
  describe "awaiting_summary_batch exemption from the abandoned sweep" do
    def quiet_batch_run(quiet_for: described_class::ABANDONED_AFTER + 1.minute, **attrs)
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, **attrs)
      described_class.where(id: run.id).update_all(updated_at: quiet_for.ago)
      run.reload
    end

    before do
      allow(described_class).to receive(:solid_queue_job_exists_for?).and_return(false)
    end

    it "is not abandoned while quiet and the batch has not expired" do
      run = quiet_batch_run(summary_batch_expires_at: 1.hour.from_now)
      expect(run).not_to be_abandoned
    end

    it "is not offered as an abandoned_candidates row while the batch has not expired" do
      run = quiet_batch_run(summary_batch_expires_at: 1.hour.from_now)
      expect(described_class.abandoned_candidates).not_to include(run)
    end

    it "is abandoned once quiet past the batch's own expiry" do
      run = quiet_batch_run(summary_batch_expires_at: 1.minute.ago)
      expect(run).to be_abandoned
    end

    it "is offered as an abandoned_candidates row once quiet past the batch's own expiry" do
      run = quiet_batch_run(summary_batch_expires_at: 1.minute.ago)
      expect(described_class.abandoned_candidates).to include(run)
    end

    it "treats a nil batch expiry as reclaimable rather than waiting forever" do
      run = quiet_batch_run(summary_batch_expires_at: nil)
      expect(run).to be_abandoned
      expect(described_class.abandoned_candidates).to include(run)
    end

    it "still defers to a live job past the batch's expiry" do
      allow(described_class).to receive(:solid_queue_job_exists_for?).and_return(true)
      run = quiet_batch_run(summary_batch_expires_at: 1.minute.ago)
      expect(run).not_to be_abandoned
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#Why resume draws the same line as abandonment]]
  describe "#summary_batch_awaited?" do
    it "is true while awaiting_summary_batch and the expiry has not passed" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: 1.hour.from_now)
      expect(run).to be_summary_batch_awaited
    end

    it "is false once the expiry has passed" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: 1.minute.ago)
      expect(run).not_to be_summary_batch_awaited
    end

    it "is false when no expiry was recorded" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch, summary_batch_expires_at: nil)
      expect(run).not_to be_summary_batch_awaited
    end

    it "is false for any status other than awaiting_summary_batch" do
      run = create(:legislation_pipeline_run, status: "summarizing")
      create(:pipeline_run_summary_batch, legislation_pipeline_run: run, expires_at: 1.hour.from_now)

      expect(run.reload).not_to be_summary_batch_awaited
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#Why chunking is a progress decision, not a cost one]]
  describe "a run owning many summary batches" do
    before do
      allow(described_class).to receive(:solid_queue_job_exists_for?).and_return(false)
    end

    def quiet_awaiting_run(expiries)
      run = create(:legislation_pipeline_run, status: "awaiting_summary_batch", current_stage: "summarize")
      expiries.each do |expires_at|
        create(:pipeline_run_summary_batch, legislation_pipeline_run: run, expires_at: expires_at)
      end
      described_class.where(id: run.id).update_all(updated_at: (described_class::ABANDONED_AFTER + 1.minute).ago)
      run.reload
    end

    it "is awaited while its one batch is still live" do
      expect(quiet_awaiting_run([1.hour.from_now])).to be_summary_batch_awaited
    end

    it "is awaited while any one of several batches is still live" do
      expect(quiet_awaiting_run([2.minutes.ago, 1.hour.from_now, nil])).to be_summary_batch_awaited
    end

    it "is not awaited once every batch has expired" do
      expect(quiet_awaiting_run([2.minutes.ago, 1.minute.ago])).not_to be_summary_batch_awaited
    end

    it "is not awaited when a batch recorded no expiry" do
      expect(quiet_awaiting_run([nil])).not_to be_summary_batch_awaited
    end

    it "is not awaited when it owns no batches at all" do
      expect(quiet_awaiting_run([])).not_to be_summary_batch_awaited
    end

    it "offers the same rows as candidates that the predicate would call abandoned" do
      one_live = quiet_awaiting_run([1.hour.from_now])
      some_live = quiet_awaiting_run([2.minutes.ago, 1.hour.from_now])
      all_expired = quiet_awaiting_run([2.minutes.ago, 1.minute.ago])
      no_expiry = quiet_awaiting_run([nil])
      no_batches = quiet_awaiting_run([])

      candidates = described_class.abandoned_candidates.to_a

      expect(candidates).to include(all_expired, no_expiry, no_batches)
      expect(candidates).not_to include(one_live, some_live)

      [one_live, some_live, all_expired, no_expiry, no_batches].each do |run|
        expect(candidates.include?(run)).to be(run.abandoned?),
          "abandoned_candidates and #abandoned? disagree about run ##{run.id}"
      end
    end
  end

  describe "orphan_age_candidates excludes awaiting_summary_batch" do
    it "does not offer a stale awaiting_summary_batch row" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch)
      described_class.where(id: run.id).update_all(created_at: described_class::ORPHAN_AGE_THRESHOLD.ago - 1.minute)

      expect(described_class.orphan_age_candidates).not_to include(run.reload)
    end
  end

  describe "#reopen_stuck_stage!" do
    before do
      allow(PipelineActivityLogger).to receive(:emit_state_transition!)
      allow(PipelineRunChannel).to receive(:broadcast_to)
    end

    it "moves a run out of every per-stage status it can be stuck in" do
      described_class::PHASE_52_STAGE_STATES.each do |stage_state|
        run = create(:legislation_pipeline_run, status: stage_state.to_s)

        expect(run.reopen_stuck_stage!).to be(true)
        expect(run.reload.status).to eq("running")
      end
    end

    it "records the move in the Activity Log, named for what really happened" do
      run = create(:legislation_pipeline_run, status: "fetching_law")

      run.reopen_stuck_stage!

      # Not "complete_fetch_law". Nobody completed anything, and a reader of the
      # log has to be able to tell a stage that finished from one that was
      # abandoned and reopened.
      expect(PipelineActivityLogger).to have_received(:emit_state_transition!).with(
        run: run, from: "fetching_law", to: "running", event: "reopen_stuck_stage"
      ).once
    end

    it "tells the open screens, so nobody has to reload to see the run move" do
      run = create(:legislation_pipeline_run, status: "fetching_law", remote_run_id: "rid-stuck")

      run.reopen_stuck_stage!

      expect(PipelineRunChannel).to have_received(:broadcast_to).with(
        anything,
        hash_including(scope: "run", run_id: run.id, status: "running", from: "fetching_law", to: "running")
      ).once
    end

    # The statuses it must leave alone are the ones a person or the machine put
    # there on purpose. Reopening a cancelled run would restart work an operator
    # stopped.
    it "changes nothing for a run that is not inside a stage" do
      %w[queued running succeeded partial failed cancelled].each do |settled_status|
        run = create(:legislation_pipeline_run, status: settled_status)

        expect(run.reopen_stuck_stage!).to be(false)
        expect(run.reload.status).to eq(settled_status)
      end

      expect(PipelineActivityLogger).not_to have_received(:emit_state_transition!)
      expect(PipelineRunChannel).not_to have_received(:broadcast_to)
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#What the operator sees while a batch is outstanding]]
  describe "to_builder summary_batch" do
    it "sends null for a run that submitted no summary batch" do
      run = create(:legislation_pipeline_run)

      props = JSON.parse(run.to_builder.target!)

      expect(props).to have_key("summary_batch")
      expect(props["summary_batch"]).to be_nil
    end

    it "serializes the exact key set the pipeline tab reads" do
      run = create(:legislation_pipeline_run, :awaiting_summary_batch)

      batch = JSON.parse(run.reload.to_builder.target!).fetch("summary_batch")

      expect(batch.keys).to contain_exactly(
        "awaiting",
        "batches_total",
        "batches_ingested",
        "items_total",
        "items_succeeded",
        "items_failed",
        "first_submitted_at",
        "expires_at"
      )
    end

    it "adds the per-chunk counts up across every batch the run submitted" do
      run = create(:legislation_pipeline_run, status: "awaiting_summary_batch")
      create(:pipeline_run_summary_batch, legislation_pipeline_run: run,
        item_count: 100, succeeded_count: 97, errored_count: 2, canceled_count: 1,
        ingested_at: 30.seconds.ago)
      create(:pipeline_run_summary_batch, legislation_pipeline_run: run, item_count: 60)

      batch = JSON.parse(run.reload.to_builder.target!).fetch("summary_batch")

      expect(batch["awaiting"]).to be(true)
      expect(batch["batches_total"]).to eq(2)
      expect(batch["batches_ingested"]).to eq(1)
      expect(batch["items_total"]).to eq(160)
      expect(batch["items_succeeded"]).to eq(97)
      # errored + canceled + expired, from the one chunk that has ended
      expect(batch["items_failed"]).to eq(3)
    end

    it "measures elapsed time from the earliest submission and the deadline from the latest expiry" do
      run = create(:legislation_pipeline_run, status: "awaiting_summary_batch")
      create(:pipeline_run_summary_batch, legislation_pipeline_run: run,
        submitted_at: Time.utc(2026, 9, 3, 10, 0, 0), expires_at: Time.utc(2026, 9, 4, 10, 0, 0))
      create(:pipeline_run_summary_batch, legislation_pipeline_run: run,
        submitted_at: Time.utc(2026, 9, 3, 9, 30, 0), expires_at: Time.utc(2026, 9, 4, 11, 15, 0))

      batch = JSON.parse(run.reload.to_builder.target!).fetch("summary_batch")

      expect(batch["first_submitted_at"]).to eq("2026-09-03T09:30:00Z")
      expect(batch["expires_at"]).to eq("2026-09-04T11:15:00Z")
    end

    it "reports awaiting=false for a run whose status has moved on from awaiting_summary_batch" do
      run = create(:legislation_pipeline_run, status: "summarizing")
      create(:pipeline_run_summary_batch, legislation_pipeline_run: run)

      batch = JSON.parse(run.reload.to_builder.target!).fetch("summary_batch")

      expect(batch["awaiting"]).to be(false)
    end
  end
end
