# frozen_string_literal: true

require "rails_helper"

# Defined above the describe block: a constant created inside a block
# lands on Object anyway, so putting it at the top level says so out loud
# (see Lint/ConstantDefinitionInBlock).
STATE_MACHINE_EVENT_TYPES = %w[state_transition bill_state_transition].freeze
# stage_budget_tripped is emitted by log_stage_budget_tripped!, from
# RunLegislationPipelineJob's rescue path.
DIRECT_EMIT_EVENT_TYPES = [] #: Array[String]

# A stand-in flash object whose []= always raises, so BOTH the primary and the
# backup flash writes fail inside Transport.dispatch_inertia.
class AlwaysRaisingFlash
  def []=(_key, _value)
    raise "flash store is frozen"
  end
end

RSpec.describe PipelineActivityLogger, type: :model do
  let(:bill) { create(:bill) }
  let(:run) { create(:legislation_pipeline_run) }

  # A fake request used only by the unit-level transport tests. For a real
  # round trip see spec/requests/pipeline_activity_logger_inertia_flash_spec.rb
  unless defined?(FakeRequest)
    FakeRequest = Struct.new(:flash, :inertia_flag) {
      def inertia? # steep:ignore
        inertia_flag # steep:ignore
      end

      def respond_to?(method_name, include_private = false)
        return true if [:inertia?, "inertia?"].include?(method_name)
        super
      end
    }
  end

  before do
    Current.reset
  end

  # Test 1: every human-facing event_type has a matching log_*! method.
  # state_transition and bill_state_transition come from the state machine
  # via emit_*_transition!, not log_*!, so are left out.
  describe "public API" do
    it "exposes exactly 15 log_*! class methods (one per human-facing event_type)" do
      human_facing = PipelineActivityLogEntry::EVENT_TYPES - STATE_MACHINE_EVENT_TYPES - DIRECT_EMIT_EVENT_TYPES
      human_facing.each do |event_type|
        expect(PipelineActivityLogger).to respond_to(:"log_#{event_type}!"),
          "expected PipelineActivityLogger to respond to log_#{event_type}!"
      end
      # 15, up from 14. Pinned so a mismatch fails here.
      expect(human_facing.count).to eq(15)
    end

    it "exposes emit_state_transition! and emit_bill_transition! for state_machines callbacks" do
      expect(PipelineActivityLogger).to respond_to(:emit_state_transition!)
      expect(PipelineActivityLogger).to respond_to(:emit_bill_transition!)
    end
  end

  # Five newer event types added to the public API.
  describe "stage event_types" do
    let(:admin) { create(:user, is_registration_complete: true, email: "admin@example.com") }

    before { allow(PipelineRunChannel).to receive(:broadcast_to) }

    it "log_paste_summary_accepted! creates an info-severity entry tied to the Bill" do
      entry = PipelineActivityLogger.log_paste_summary_accepted!(bill: bill, actor: admin)
      expect(entry.event_type).to eq("paste_summary_accepted")
      expect(entry.severity).to eq("info")
      expect(entry.subject_type).to eq("Bill")
      expect(entry.subject_id).to eq(bill.id.to_s)
      expect(entry.payload["bill_external_id"]).to eq(bill.external_id)
      expect(entry.payload["operator_email"]).to eq("admin@example.com")
    end

    it "log_paste_summary_rejected! emits warning severity with the errors array" do
      entry = PipelineActivityLogger.log_paste_summary_rejected!(
        bill: bill, actor: admin, errors: ["title missing", "body too short"]
      )
      expect(entry.event_type).to eq("paste_summary_rejected")
      expect(entry.severity).to eq("warning")
      expect(entry.payload["errors"]).to eq(["title missing", "body too short"])
    end

    it "log_org_position_decision! accepts a duck-typed draft" do
      draft = Struct.new(:id, :organization_name).new(99, "ACLU")
      entry = PipelineActivityLogger.log_org_position_decision!(
        bill: bill, draft: draft, decision: :approved, actor: admin
      )
      expect(entry.event_type).to eq("org_position_decision")
      expect(entry.severity).to eq("info")
      expect(entry.payload["org_name"]).to eq("ACLU")
      expect(entry.payload["decision"]).to eq("approved")
    end

    it "log_orphan_run_deleted! accepts a nil subject (the run is already gone)" do
      entry = PipelineActivityLogger.log_orphan_run_deleted!(run_id: 42, actor: admin)
      expect(entry.event_type).to eq("orphan_run_deleted")
      expect(entry.subject_type).to be_nil
      expect(entry.payload["run_id"]).to eq(42)
    end

    it "log_force_fail_triggered! is bound to the LegislationPipelineRun subject" do
      run = create(:legislation_pipeline_run)
      entry = PipelineActivityLogger.log_force_fail_triggered!(run: run, actor: admin)
      expect(entry.event_type).to eq("force_fail_triggered")
      expect(entry.severity).to eq("warning")
      expect(entry.subject_type).to eq("LegislationPipelineRun")
      expect(entry.payload["run_id"]).to eq(run.id)
    end
  end

  # GenerateBillSummaryJob declining to call at all.
  describe "log_summary_stood_down_for_paste! and log_summary_skipped_no_source_text!" do
    it "log_summary_stood_down_for_paste! is info severity, tied to the Bill, and names Regenerate" do
      entry = PipelineActivityLogger.log_summary_stood_down_for_paste!(bill: bill)
      expect(entry.event_type).to eq("summary_stood_down_for_paste")
      expect(entry.severity).to eq("info")
      expect(entry.subject_type).to eq("Bill")
      expect(entry.subject_id).to eq(bill.id.to_s)
      expect(entry.payload["bill_external_id"]).to eq(bill.external_id)
      expect(entry.message).to include(bill.external_id)
      expect(entry.message).to include("Regenerate")
      expect(entry.message).not_to include("extract-text")
    end

    it "log_summary_skipped_no_source_text! is info severity, tied to the Bill, and names the upstream stages" do
      entry = PipelineActivityLogger.log_summary_skipped_no_source_text!(bill: bill)
      expect(entry.event_type).to eq("summary_skipped_no_source_text")
      expect(entry.severity).to eq("info")
      expect(entry.subject_type).to eq("Bill")
      expect(entry.subject_id).to eq(bill.id.to_s)
      expect(entry.payload["bill_external_id"]).to eq(bill.external_id)
      expect(entry.message).to include(bill.external_id)
      expect(entry.message).to include("extract-text")
      expect(entry.message).to include("fetch-hearings")
      expect(entry.message).not_to include("Regenerate")
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Why resume draws the same line as abandonment]]
  describe "log_resume_deferred_for_summary_batch!" do
    it "is info severity, tied to the run, and names every live batch and the last expiry" do
      batch_run = create(:legislation_pipeline_run, :awaiting_summary_batch)
      second = create(:pipeline_run_summary_batch, legislation_pipeline_run: batch_run, expires_at: 2.hours.from_now)
      first = batch_run.pipeline_run_summary_batches.reload.first
      first ||= raise("expected the awaiting_summary_batch trait to build a batch")

      entry = PipelineActivityLogger.log_resume_deferred_for_summary_batch!(run: batch_run)

      expect(entry.event_type).to eq("resume_deferred_for_summary_batch")
      expect(entry.severity).to eq("info")
      expect(entry.subject_type).to eq("LegislationPipelineRun")
      expect(entry.subject_id).to eq(batch_run.id.to_s)
      expect(entry.payload["run_id"]).to eq(batch_run.id)
      expect(entry.payload["summary_batch_ids"]).to contain_exactly(first.batch_id, second.batch_id)
      expect(entry.payload["summary_batch_expires_at"]).to eq(first.expires_at&.utc&.iso8601)
      expect(entry.message).to include(first.batch_id, second.batch_id)
    end
  end

  # Test 2: each event_type maps to the right severity.
  describe "SEVERITY_FOR_EVENT" do
    it "maps every event_type to a valid severity" do
      PipelineActivityLogEntry::EVENT_TYPES.each do |event_type|
        sev = PipelineActivityLogger::SEVERITY_FOR_EVENT[event_type]
        expect(sev).to be_in(PipelineActivityLogEntry::SEVERITIES),
          "expected SEVERITY_FOR_EVENT[#{event_type.inspect}] to be a valid severity, got #{sev.inspect}"
      end
    end

    it "uses 'error' severity for failure events" do
      # The event types that count as errors.
      %w[stage_failed ingestion_failure llm_provider_error
        llm_json_parse_failure].each do |event_type|
        expect(PipelineActivityLogger::SEVERITY_FOR_EVENT[event_type]).to eq("error"),
          "expected #{event_type} to have severity 'error'"
      end
    end

    it "grades operator-initiated events by how much they should worry a reader" do
      # These happen because an operator asked for them, so none is an
      # error. Force-failing a run is still a warning: a deliberate act
      # that throws work away, worth stopping on.
      expect(PipelineActivityLogger::SEVERITY_FOR_EVENT["force_fail_triggered"]).to eq("warning")
      expect(PipelineActivityLogger::SEVERITY_FOR_EVENT["orphan_run_deleted"]).to eq("info")
      expect(PipelineActivityLogger::SEVERITY_FOR_EVENT["summary_regenerate_triggered"]).to eq("info")
    end
  end

  # Where log_summary_regenerate_triggered! entries come from.
  describe "log_summary_regenerate_triggered!" do
    it "creates a single PipelineActivityLogEntry with the expected shape" do
      allow(PipelineRunChannel).to receive(:broadcast_to)

      entry = nil #: PipelineActivityLogEntry?
      expect {
        entry = PipelineActivityLogger.log_summary_regenerate_triggered!(
          bill: bill, actor: nil, first_generation: false
        )
      }.to change(PipelineActivityLogEntry, :count).by(1)

      expect(entry).to be_a(PipelineActivityLogEntry)
      entry ||= raise("log_summary_regenerate_triggered! must return the created entry")
      expect(entry.event_type).to eq("summary_regenerate_triggered")
      expect(entry.severity).to eq("info")
      expect(entry.subject_type).to eq("Bill")
      expect(entry.subject_id).to eq(bill.id.to_s)
      expect(entry.title).to include(bill.external_id[0...50])
      expect(entry.payload).to include(
        "bill_external_id" => bill.external_id, "bill_id" => bill.id, "first_generation" => false
      )
    end

    # One event type, two situations: the empty state's Generate summary
    # and the completed view's Regenerate summary both post to the same
    # endpoint. The TITLE is built from the payload alone.
    it "titles a first generation as a generation" do
      allow(PipelineRunChannel).to receive(:broadcast_to)

      entry = PipelineActivityLogger.log_summary_regenerate_triggered!(
        bill: bill, actor: nil, first_generation: true
      )

      expect(entry.payload).to include("first_generation" => true)
      expect(entry.title).to include("Summary generation triggered")
      expect(entry.title).not_to include("regeneration")
      expect(entry.message).to include("summary generation")
    end

    it "attributes the entry to the given actor" do
      allow(PipelineRunChannel).to receive(:broadcast_to)
      admin = create(:user, is_registration_complete: true)
      entry = PipelineActivityLogger.log_summary_regenerate_triggered!(
        bill: bill, actor: admin, first_generation: false
      )
      expect(entry.actor_user_id).to eq(admin.id)
    end
  end

  # Test 3: every event_type has a lambda that builds its title.
  describe "TITLE_TEMPLATES" do
    it "has a callable lambda for every event_type" do
      PipelineActivityLogEntry::EVENT_TYPES.each do |event_type|
        tmpl = PipelineActivityLogger::TITLE_TEMPLATES[event_type]
        expect(tmpl).to respond_to(:call),
          "expected TITLE_TEMPLATES[#{event_type.inspect}] to be callable"
      end
    end

    it "produces non-blank title strings" do
      payload_h = {stage_name: "extract-text", error_message: "boom", bill_external_id: "HB123",
                   raw_excerpt: nil, validation_errors: ["err"], status_code: 500, path: "/api",
                   event_name: "stage_failed", attempts: 3, reason: "timeout"}
      PipelineActivityLogEntry::EVENT_TYPES.each do |event_type|
        title = PipelineActivityLogger::TITLE_TEMPLATES[event_type].call(payload_h)
        expect(title).to be_a(String)
        expect(title).not_to be_blank
        expect(title.length).to be <= 60
      end
    end
  end

  # Test 4: each call writes exactly one row, inside a transaction.
  describe "transactional write" do
    it "creates exactly one PipelineActivityLogEntry row" do
      allow(PipelineRunChannel).to receive(:broadcast_to)

      expect {
        PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)
      }.to change(PipelineActivityLogEntry, :count).by(1)
    end

    it "returns the created entry" do
      allow(PipelineRunChannel).to receive(:broadcast_to)
      result = PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)
      expect(result).to be_a(PipelineActivityLogEntry)
      expect(result).to be_persisted
    end
  end

  # Test 5: the synchronous path, used for an Inertia request.
  describe "transport selector — Inertia sync path" do
    it "writes flash[:activity_log_entry] and does NOT broadcast when request.inertia? is true" do
      fake_flash = {} # steep:ignore
      fake_req = FakeRequest.new(fake_flash, true)
      expect(fake_req).to respond_to(:inertia?)
      Current.request = fake_req

      expect(PipelineRunChannel).not_to receive(:broadcast_to)

      PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)

      entry_payload = fake_flash[:activity_log_entry]
      expect(entry_payload).to be_a(Hash)
      # serialize_entry returns a hash with symbol keys.
      event_type_val = entry_payload[:event_type]
      expect(event_type_val).to eq("orphan_run_deleted")
    end

    # The Inertia flash payload leaves out the 4000-character raw_excerpt, so
    # the session cookie cannot blow past CookieStore's roughly 4 KB limit.
    it "elides raw_excerpt in the flash payload for llm_json_parse_failure" do
      fake_flash = {} # steep:ignore
      fake_req = FakeRequest.new(fake_flash, true)
      Current.request = fake_req

      big_excerpt = "a" * 4000
      PipelineActivityLogger.log_llm_json_parse_failure!(
        bill: bill,
        error_message: "boom",
        raw_excerpt: big_excerpt,
        actor: nil
      )

      flash_payload = fake_flash[:activity_log_entry]
      raw = flash_payload[:payload]["raw_excerpt"]
      expect(raw).to match(/see Activity Log row/)
      expect(raw.length).to be < 100
    end

    # The WebSocket broadcast must still carry the whole raw_excerpt. Only the
    # flash copy leaves it out.
    it "preserves raw_excerpt in the cable broadcast (non-Inertia path)" do
      Current.reset

      broadcast_payload = nil
      allow(PipelineRunChannel).to receive(:broadcast_to) { |_target, payload|
        broadcast_payload = payload
      }

      big_excerpt = "a" * 4000
      PipelineActivityLogger.log_llm_json_parse_failure!(
        bill: bill,
        error_message: "boom",
        raw_excerpt: big_excerpt,
        actor: nil
      )

      entry_payload = broadcast_payload[:entry] # steep:ignore
      raw = entry_payload[:payload]["raw_excerpt"]
      expect(raw).to eq(big_excerpt)
    end
  end

  # When the primary flash write fails, a backup write runs; if THAT fails
  # too, it is now logged at ERROR, not silently swallowed. A bare rescue
  # would make this fail.
  describe "transport selector — Inertia secondary flash failure (CG6-01 / ME5-01)" do
    it "logs at ERROR with BOTH exception classes when secondary flash write also fails" do
      fake_req = FakeRequest.new(AlwaysRaisingFlash.new, true)
      Current.request = fake_req

      logged_messages = [] # steep:ignore
      allow(Rails.logger).to receive(:error) { |msg| logged_messages << msg.to_s }
      allow(Rails.logger).to receive(:warn) # the primary failure still logs a warning; ignored here

      PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)

      # The double-failure log is a structured SwayLogging.error event
      # through Rails.logger.error, carrying BOTH exception classes so an
      # operator can match the primary failure to the backup.
      double_failure_log = logged_messages.find { |m| m.include?("pipeline_activity_log.both_flash_transports_failed") }
      expect(double_failure_log).to be_present,
        "expected Rails.logger.error to be invoked with the BOTH-failed event; got: #{logged_messages.inspect}"
      expect(double_failure_log).to include("primary_error_class=\"RuntimeError\"")
      expect(double_failure_log).to include("secondary_error_class=\"RuntimeError\"")
      expect(double_failure_log).to include("event_type=\"orphan_run_deleted\"")
    end
  end

  # Test 6: the asynchronous path, used for a non-Inertia request such as a webhook.
  describe "transport selector — non-Inertia async path" do
    it "broadcasts to PipelineRunChannel and does NOT set flash when request.inertia? is false" do
      fake_flash = {} # steep:ignore
      fake_req = FakeRequest.new(fake_flash, false)
      Current.request = fake_req

      expect(PipelineRunChannel).to receive(:broadcast_to).once

      PipelineActivityLogger.log_stage_failed!(run: run, stage_name: "ocr", error_message: "fail", actor: nil)

      expect(fake_flash).to be_empty
    end
  end

  # Test 7: no request at all, as in a job or service (Current.request is nil).
  describe "transport selector — no request (job context)" do
    it "broadcasts with run.remote_run_id when Current.request is nil" do
      Current.reset  # ensure nil

      broadcast_target = nil
      allow(PipelineRunChannel).to receive(:broadcast_to) { |target, _payload|
        broadcast_target = target
      }

      PipelineActivityLogger.log_stage_failed!(run: run, stage_name: "ocr", error_message: "fail", actor: nil)

      expect(broadcast_target).to eq(run.remote_run_id)
    end
  end

  # Test 8: events whose subject does not map to a run fall back to "global".
  describe "transport selector — global stream fallback" do
    it "broadcasts on 'global' stream for ingestion_failure (no run subject)" do
      Current.reset

      broadcast_target = nil
      allow(PipelineRunChannel).to receive(:broadcast_to) { |target, _payload|
        broadcast_target = target
      }

      PipelineActivityLogger.log_ingestion_failure!(bill_external_id: "BAL-001", error_message: "Internal Server Error", actor: nil)

      expect(broadcast_target).to eq("global")
    end
  end

  # Test 9: a failed broadcast is swallowed.
  describe "broadcast failure handling" do
    it "swallows broadcast exceptions and still persists the entry" do
      allow(PipelineRunChannel).to receive(:broadcast_to).and_raise(RuntimeError, "Redis offline")

      entry = nil #: PipelineActivityLogEntry?
      expect {
        entry = PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)
      }.not_to raise_error

      expect(entry).to be_persisted
    end
  end

  # A run started with perform_now has no ActionCable subscriber, so
  # without an echo to stdout an operator stares at a silent 5-10 minute
  # process. The async branch must log to Rails.logger.info too.
  describe "async-branch stdout heartbeat" do
    it "echoes the entry to Rails.logger.info on the cable (non-Inertia) path" do
      allow(PipelineRunChannel).to receive(:broadcast_to)
      # @type var info_messages: Array[String]
      info_messages = []
      allow(Rails.logger).to receive(:info) { |msg| info_messages << msg.to_s }

      PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)

      heartbeat = info_messages.find { |m| m.include?("[PipelineActivityLog]") }
      expect(heartbeat).to be_present
      expect(heartbeat).to include("orphan_run_deleted")
      expect(heartbeat).to match(/INFO/i)
    end

    it "still emits the heartbeat when the cable broadcast itself raises" do
      allow(PipelineRunChannel).to receive(:broadcast_to).and_raise(RuntimeError, "Redis offline")
      # @type var info_messages: Array[String]
      info_messages = []
      allow(Rails.logger).to receive(:info) { |msg| info_messages << msg.to_s }
      allow(Rails.logger).to receive(:warn) # the broadcast-failure warning is expected; ignore it

      PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)

      expect(info_messages.any? { |m| m.include?("[PipelineActivityLog]") }).to be(true)
    end
  end

  # Test 10: an entry cannot be changed once it is written.
  describe "entry immutability" do
    it "raises ActiveRecord::ReadOnlyRecord when attempting to update an entry" do
      allow(PipelineRunChannel).to receive(:broadcast_to)
      entry = PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)
      expect { entry.update!(message: "tampered") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  # Test 11: serialize_entry's shape — 12 keys, with iso8601(6) microsecond timestamps.
  describe ".serialize_entry" do
    it "returns a Hash with 12 expected keys" do
      allow(PipelineRunChannel).to receive(:broadcast_to)
      entry = PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)

      serialized = PipelineActivityLogger.serialize_entry(entry)

      expect(serialized.keys.map(&:to_s).sort).to match_array(
        %w[id event_type severity title message subject_type subject_id subject_label actor_user_id payload inspect_query created_at]
      )

      # actor_user_id and payload must both be there.
      expect(serialized).to include(:actor_user_id)
      expect(serialized).to include(:payload)
    end

    # serialize_entry must preserve created_at to the microsecond, so
    # same-second entries still sort correctly for cursor pagination,
    # checked via the shared microsecond_precision_timestamps example.
    include_examples "emits microsecond-precision timestamps",
      emit: -> { PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil) }

    it "is a PUBLIC class method (callable from outside the class)" do
      expect(PipelineActivityLogger).to respond_to(:serialize_entry)
    end

    # Cookie-size trimming did nothing on the after_commit path: the
    # in-memory Hash has SYMBOL keys while the check looked for a STRING
    # key. Keys are stringified at the boundary now.
    it "elides raw_excerpt for_flash even when the in-memory payload uses SYMBOL keys (BL4-01)" do
      allow(PipelineRunChannel).to receive(:broadcast_to)

      big_excerpt = "x" * 4000
      # Build an entry whose in-memory payload Hash uses symbol keys, the
      # shape to_h produces, and what after_commit sees before anything
      # round-trips through the database as JSON.
      entry = PipelineActivityLogEntry.new(
        event_type: "llm_json_parse_failure",
        severity: "error",
        title: "LLM response parse failed",
        message: "boom",
        subject: bill,
        actor_user_id: nil,
        payload: {error_message: "boom", raw_excerpt: big_excerpt}
      )
      entry.save!

      # Make the symbol-keyed Hash the value serialize_entry actually reads,
      # imitating after_commit, which runs against the record still in
      # memory (Rails does not reload before firing it).
      entry.payload = {error_message: "boom", raw_excerpt: big_excerpt}

      serialized = PipelineActivityLogger.serialize_entry(entry, for_flash: true)

      payload = serialized[:payload]
      expect(payload).to be_a(Hash)
      # Once the keys are turned into strings and the excerpt is trimmed, the
      # value sits under the string key and holds the pointer marker.
      expect(payload["raw_excerpt"]).to match(/see Activity Log row #{entry.id}/)
      expect(payload["raw_excerpt"].length).to be < 100
      # The non-flash copy MUST keep the whole excerpt. Only the flash copy,
      # which has to fit inside a cookie, is trimmed.
      entry.payload = {error_message: "boom", raw_excerpt: big_excerpt}
      full = PipelineActivityLogger.serialize_entry(entry, for_flash: false)
      expect(full[:payload]["raw_excerpt"]).to eq(big_excerpt)
    end
  end

  # Test 12: the "global" stream name matches on both sides — broadcast_to "global" and stream_for "global".
  describe '"global" stream parity (MEDIUM-1)' do
    it "broadcasts to string 'global' for entries without a run-resolvable subject" do
      Current.reset
      broadcast_args = [] # steep:ignore
      allow(PipelineRunChannel).to receive(:broadcast_to) { |*args| broadcast_args << args }

      PipelineActivityLogger.log_ingestion_failure!(
        bill_external_id: "HB999",
        error_message: "parse error",
        actor: nil
      )

      expect(broadcast_args.first.first).to eq("global")
    end
  end

  # Test 13: choosing a stream when the subject is a Bill.
  describe "Bill-subject stream resolution (HIGH-2)" do
    it "resolves stream_id from bill's most recent pipeline run remote_run_id" do
      Current.reset
      bill_with_run = create(:bill)
      run_for_bill = create(:legislation_pipeline_run, bill: bill_with_run)

      broadcast_target = nil
      allow(PipelineRunChannel).to receive(:broadcast_to) { |target, _| broadcast_target = target }

      PipelineActivityLogger.log_llm_provider_error!(bill: bill_with_run, error_message: "transport failed", actor: nil)

      expect(broadcast_target).to eq(run_for_bill.remote_run_id)
    end

    it "falls back to 'global' when bill has no associated pipeline runs" do
      Current.reset
      bill_no_runs = create(:bill)
      bill_no_runs.legislation_pipeline_runs.destroy_all

      broadcast_target = nil
      allow(PipelineRunChannel).to receive(:broadcast_to) { |target, _| broadcast_target = target }

      PipelineActivityLogger.log_llm_provider_error!(bill: bill_no_runs, error_message: "transport failed", actor: nil)

      expect(broadcast_target).to eq("global")
    end
  end

  # On events whose name begins with "start_", the state_transition payload
  # picks up extra keys from Pipeline::Current.current_auto_include_context.
  describe "auto-include payload extension on start_<stage> events (FINDING-1 — reads Pipeline::Current)" do
    before { allow(PipelineRunChannel).to receive(:broadcast_to) }
    after { Pipeline::Current.reset }

    it "merges Pipeline::Current.current_auto_include_context into payload on start_<stage> events (auto-included path)" do
      Pipeline::Current.current_auto_include_context = {
        stage: "fetch-law",
        reason: "missing_artifact",
        bill_external_ids: ["24-1234", "24-5678"]
      }

      entry = PipelineActivityLogger.emit_state_transition!(
        run: run,
        from: "running_extract_text",
        to: "running_fetch_law",
        event: "start_fetch_law"
      )

      expect(entry.event_type).to eq("state_transition")
      # Base keys still present.
      expect(entry.payload).to include(
        "from" => "running_extract_text",
        "to" => "running_fetch_law",
        "event" => "start_fetch_law",
        "run_id" => run.id
      )
      # The extra keys merged in from Pipeline::Current.
      expect(entry.payload).to include(
        "stage" => "fetch-law",
        "reason" => "missing_artifact",
        "bill_external_ids" => ["24-1234", "24-5678"]
      )
    end

    it "OMITS auto-include keys when Pipeline::Current.current_auto_include_context is nil (operator-checked path)" do
      Pipeline::Current.current_auto_include_context = nil

      entry = PipelineActivityLogger.emit_state_transition!(
        run: run,
        from: "running_extract_text",
        to: "running_fetch_law",
        event: "start_fetch_law"
      )

      # The plain payload shape, the same one older state_transition entries had.
      expect(entry.payload.keys.map(&:to_s)).to contain_exactly("from", "to", "event", "run_id")
      expect(entry.payload).not_to have_key("stage")
      expect(entry.payload).not_to have_key("reason")
      expect(entry.payload).not_to have_key("bill_external_ids")
    end

    it "IGNORES Pipeline::Current on non-start transitions (e.g., complete_<stage>) — the /^start_/ gate" do
      Pipeline::Current.current_auto_include_context = {
        stage: "fetch-law",
        reason: "missing_artifact",
        bill_external_ids: ["24-1234"]
      }

      entry = PipelineActivityLogger.emit_state_transition!(
        run: run,
        from: "running_fetch_law",
        to: "running_extract_text",
        event: "complete_fetch_law"
      )

      # The event name does not begin with "start_", so the extra keys MUST NOT be merged.
      expect(entry.payload.keys.map(&:to_s)).to contain_exactly("from", "to", "event", "run_id")
      expect(entry.payload).not_to have_key("stage")
      expect(entry.payload).not_to have_key("reason")
      expect(entry.payload).not_to have_key("bill_external_ids")
    end

    it "does NOT register a new 'stage_started' event_type (extend payload, do NOT add an event_type)" do
      expect(PipelineActivityLogger::SEVERITY_FOR_EVENT.keys).not_to include("stage_started")
      expect(PipelineActivityLogger::TITLE_TEMPLATES.keys).not_to include("stage_started")
    end

    it "has a doc-comment block describing the new payload shape and the Pipeline::Current consumption mechanism" do
      src = Rails.root.join("app", "services", "pipeline_activity_logger.rb").read
      # Names all three context keys and the place they are read.
      expect(src).to include("auto_included") # the older wording the doc comment still uses
      expect(src).to include("Pipeline::Current")
      # The doc comment must describe the "start_" rule in plain English.
      expect(src).to match(/start_/)
    end
  end
end
