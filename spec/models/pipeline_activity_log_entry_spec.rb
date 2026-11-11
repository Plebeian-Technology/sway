# frozen_string_literal: true

# == Schema Information
#
# Table name: pipeline_activity_log_entries
# Database name: primary
#
#  id            :integer          not null, primary key
#  event_type    :string           not null
#  message       :string           not null
#  payload       :text             default({}), not null
#  severity      :string           not null
#  subject_type  :string
#  title         :string           not null
#  created_at    :datetime         not null
#  actor_user_id :integer
#  subject_id    :string
#
# Indexes
#
#  index_activity_log_entries_on_created_at_desc         (created_at DESC)
#  index_activity_log_entries_on_subject_polymorphic     (subject_type,subject_id)
#  index_activity_log_severity_and_created_at            (severity,created_at DESC)
#  index_pipeline_activity_log_entries_on_actor_user_id  (actor_user_id)
#  index_pipeline_activity_log_entries_on_event_type     (event_type)
#
# Foreign Keys
#
#  actor_user_id  (actor_user_id => users.id)
#
require "rails_helper"

RSpec.describe PipelineActivityLogEntry, type: :model do
  let(:bill) { create(:bill) }
  let(:run) { create(:legislation_pipeline_run, bill: bill) }

  let(:valid_attrs) do
    {
      event_type: "stage_failed",
      severity: "error",
      title: "Stage failed: extract-text",
      message: "Pipeline run abc123 failed at extract-text",
      payload: {stage_name: "extract-text", error_message: "timeout"}
    }
  end

  # An entry's subject can be any kind of record, not just rows from one table.
  it "belongs_to subject polymorphically (LegislationPipelineRun)" do
    entry = described_class.create!(valid_attrs.merge(subject: run))
    expect(entry.subject_type).to eq("LegislationPipelineRun")
    expect(entry.subject_id.to_s).to eq(run.id.to_s)
    expect(entry.subject).to eq(run)
  end

  it "belongs_to subject polymorphically (Bill)" do
    entry = described_class.create!(
      valid_attrs.merge(
        subject: bill,
        event_type: "ingestion_failure",
        title: "Ingestion failed: BAL-001"
      )
    )
    expect(entry.subject_type).to eq("Bill")
    expect(entry.subject_id.to_s).to eq(bill.id.to_s)
    expect(entry.subject).to eq(bill)
  end

  # The payload column holds JSON, and it must come back out the way it went in.
  it "round-trips the payload column through JSON" do
    payload = {stage_name: "extract-text", error_message: "upstream timeout"}
    entry = described_class.create!(valid_attrs.merge(payload: payload))
    reloaded = described_class.find(entry.id)
    expect(reloaded.payload).to eq(payload.stringify_keys)
  end

  # Entries are written once and never edited: saved rows are read-only, and there is
  # no updated_at column.
  it "is read-only after persisting" do
    entry = described_class.create!(valid_attrs)
    expect { entry.update!(message: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "has no updated_at column" do
    expect(described_class.column_names).not_to include("updated_at")
  end

  # The short label shown for whatever the entry points at.
  it "computes subject_label for the three subject_type variants" do
    run_entry = described_class.create!(valid_attrs.merge(subject: run))
    expect(run_entry.subject_label).to eq("Run #{run.remote_run_id[0..7]}")

    bill_entry = described_class.create!(
      valid_attrs.merge(
        subject: bill,
        event_type: "ingestion_failure",
        title: "Ingestion failed: #{bill.external_id}"
      )
    )
    expect(bill_entry.subject_label).to eq(bill.external_id)

    # A stage has no table of its own. Entries about one store the word "Stage" as
    # subject_type and the stage name as subject_id. insert! writes the row straight
    # to SQL, past ActiveRecord and the read-only rule it enforces. Then look the row
    # back up to check it.
    described_class.insert!({
      event_type: "stage_failed",
      severity: "error",
      title: "Stage failed: extract-text",
      message: "failed at extract-text",
      subject_type: "Stage",
      subject_id: "extract-text",
      payload: "{}",
      created_at: Time.current
    })
    stage_entry = described_class.where(subject_type: "Stage").order(created_at: :desc).first
    expect(stage_entry.subject_label).to eq("extract-text")
  end

  it "validates event_type inclusion" do
    entry = described_class.new(valid_attrs.merge(event_type: "bad_event"))
    expect(entry).not_to be_valid
    expect(entry.errors[:event_type]).to be_present
  end

  it "validates severity inclusion" do
    entry = described_class.new(valid_attrs.merge(severity: "CRITICAL"))
    expect(entry).not_to be_valid
    expect(entry.errors[:severity]).to be_present
  end

  it "validates title length max 60" do
    entry = described_class.new(valid_attrs.merge(title: "x" * 61))
    expect(entry).not_to be_valid
    expect(entry.errors[:title]).to be_present
  end

  # A Bill can list its own pipeline runs — the other side of the association.
  it "exposes Bill#legislation_pipeline_runs (HIGH-2)" do
    fresh_run = create(:legislation_pipeline_run, bill: bill)
    expect(bill.legislation_pipeline_runs.order(created_at: :desc).first).to eq(fresh_run)
  end

  # @lat: [[pipeline-activity-log-cleanup-delete-all-callback-skip#Why PipelineActivityLogEntry must never gain a destroy callback]]
  describe "delete_all skip-callback invariant (MEDIUM-4 / MEDIUM-8)" do
    it "has no dependent: :destroy associations" do
      destroy_dependents = described_class.reflect_on_all_associations.select do |assoc|
        assoc.options[:dependent] == :destroy
      end
      expect(destroy_dependents).to be_empty,
        "Adding dependent: :destroy would be silently skipped by PipelineActivityLogCleanupJob's delete_all"
    end

    it "has no operator-defined before_destroy callbacks" do
      # Read the destroy callback chain itself. Rails adds its own
      # :destroy_associations callback whenever a `dependent: :destroy` exists, so
      # that one is filtered out. Callbacks people write show up either as a method
      # name or as an anonymous block.
      operator_destroy_callbacks = described_class._destroy_callbacks
        .reject { |cb| cb.filter == :destroy_associations }
        .reject { |cb| cb.filter.is_a?(Symbol) && cb.filter.to_s.start_with?("_") }
        .map(&:filter)
      expect(operator_destroy_callbacks).to be_empty,
        "before_destroy callbacks would be silently skipped by PipelineActivityLogCleanupJob's delete_all"
    end

    # @lat: [[pipeline-activity-log-cleanup-delete-all-callback-skip#Why PipelineActivityLogEntry must never gain a destroy callback]]
    # Teardown MUST use skip_callback(:destroy, :before, callback_proc), never reset_callbacks(:destroy) —
    # the latter wipes Rails' own :destroy_associations callback for the rest of the process.
    it "delete_all bypasses before_destroy callbacks (proves the invariant matters)" do
      callback_fired = 0
      callback_proc = -> { callback_fired += 1 }
      described_class.set_callback(:destroy, :before, callback_proc)

      begin
        described_class.create!(valid_attrs)
        described_class.create!(valid_attrs)
        expect(described_class.count).to be >= 2

        # The whole point of the test: delete_all skips callbacks.
        described_class.delete_all
        expect(callback_fired).to eq(0),
          "delete_all unexpectedly invoked before_destroy — if so, MEDIUM-8's premise is wrong and the cleanup job is safe to add callbacks/associations to"
        expect(described_class.count).to eq(0)
      ensure
        # Remove only the callback this test added, by handing back the same block.
        # Rails' own callbacks stay where they are.
        described_class.skip_callback(:destroy, :before, callback_proc)
      end
    end
  end

  # @lat: [[pipeline-activity-log-inspect-query#Query text per event type]]
  describe "#inspect_query" do
    def build_entry(event_type:, payload:, subject: nil, severity: "info", title: "T", message: "M")
      described_class.create!(
        event_type: event_type,
        severity: severity,
        title: title,
        message: message,
        payload: payload,
        subject: subject
      )
    end

    def assert_parseable_ruby(source)
      RubyVM::AbstractSyntaxTree.parse(source)
    rescue SyntaxError => e
      raise RSpec::Expectations::ExpectationNotMetError,
        "inspect_query returned non-parseable Ruby: #{source.inspect}\n#{e.message}"
    end

    it "builds an OrganizationBillPosition lookup for org_position_decision" do
      entry = build_entry(
        event_type: "org_position_decision",
        payload: {"bill_id" => 42, "bill_external_id" => "25-0003", "draft_id" => 1, "org_name" => "ACLU", "decision" => "approved", "operator_email" => "a@b"}
      )

      query = entry.inspect_query
      expect(query).to include("OrganizationBillPosition")
      expect(query).to include("42")
      expect(query).to include('"ACLU"')
      assert_parseable_ruby(query)
    end

    it "escapes embedded quotes in org_name so the snippet stays parseable" do
      entry = build_entry(
        event_type: "org_position_decision",
        payload: {"bill_id" => 1, "bill_external_id" => "x", "draft_id" => 0, "org_name" => %(O'Brien "& Co"), "decision" => "approved", "operator_email" => nil}
      )

      query = entry.inspect_query
      assert_parseable_ruby(query)
    end

    %w[paste_summary_accepted paste_summary_rejected].each do |evt|
      it "builds a BillLlmProvisioning lookup for #{evt}" do
        entry = build_entry(
          event_type: evt,
          payload: {"bill_id" => 99, "bill_external_id" => "25-0007", "operator_email" => "a@b"}
        )

        query = entry.inspect_query
        expect(query).to include("BillLlmProvisioning")
        expect(query).to include("99")
        assert_parseable_ruby(query)
      end
    end

    it "builds a LegislationPipelineRun.find for force_fail_triggered" do
      entry = build_entry(
        event_type: "force_fail_triggered",
        payload: {"run_id" => 12, "remote_run_id" => "abc", "operator_email" => "a@b"}
      )

      query = entry.inspect_query
      expect(query).to include("LegislationPipelineRun.find(12)")
      assert_parseable_ruby(query)
    end

    it "builds a LegislationPipelineRun.where (with destroyed-row note) for orphan_run_deleted" do
      entry = build_entry(
        event_type: "orphan_run_deleted",
        payload: {"run_id" => 13, "operator_email" => "a@b"}
      )

      query = entry.inspect_query
      expect(query).to include("LegislationPipelineRun.where(id: 13)")
      expect(query).to match(/#.*destroyed|#.*pipeline_activity_log_entries/i)
      assert_parseable_ruby(query)
    end

    it "builds a LegislationPipelineRun.find for state_transition" do
      entry = build_entry(
        event_type: "state_transition",
        payload: {"from" => "running", "to" => "succeeded", "event" => "mark_succeeded", "run_id" => 7}
      )

      query = entry.inspect_query
      expect(query).to include("LegislationPipelineRun.find(7)")
      assert_parseable_ruby(query)
    end

    it "builds a PipelineRunBill.find for bill_state_transition" do
      entry = build_entry(
        event_type: "bill_state_transition",
        payload: {"from" => "running", "to" => "succeeded", "event" => "mark_succeeded", "bill_run_id" => 5, "bill_external_id" => "25-0001", "legislation_pipeline_run_id" => 7}
      )

      query = entry.inspect_query
      expect(query).to include("PipelineRunBill.find(5)")
      assert_parseable_ruby(query)
    end

    it "falls back to a PipelineActivityLogEntry.find for unmapped event_types" do
      # stage_failed is a valid event type, but no special lookup is defined for it,
      # so the snippet falls back to fetching the log entry itself.
      entry = build_entry(
        event_type: "stage_failed",
        severity: "error",
        payload: {"stage" => "extract_text", "reason" => "OCR_DISABLED"}
      )

      query = entry.inspect_query
      expect(query).to include("PipelineActivityLogEntry.find(#{entry.id})")
      assert_parseable_ruby(query)
    end

    it "handles symbol-keyed payloads (in-memory Hash before DB round-trip)" do
      entry = described_class.new(
        event_type: "force_fail_triggered",
        severity: "warning",
        title: "T", message: "M",
        payload: {run_id: 99, remote_run_id: "abc", operator_email: "a@b"}
      )

      query = entry.inspect_query
      expect(query).to include("LegislationPipelineRun.find(99)")
      assert_parseable_ruby(query)
    end
  end
end
