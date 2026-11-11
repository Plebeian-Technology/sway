# frozen_string_literal: true

require "rails_helper"

# @lat: [[pipeline-activity-log-auto-included-stage-context#Why Pipeline::Current uses ActiveSupport::CurrentAttributes, not Thread.current]]
RSpec.describe Pipeline::Current do
  after { described_class.reset }

  describe "current_auto_include_context" do
    it "defaults to nil before any write (fresh CurrentAttributes)" do
      expect(described_class.current_auto_include_context).to be_nil
    end

    it "round-trips a Hash: assignment returns the same Hash on read" do
      payload = {
        stage: "generate-diffs",
        reason: "missing_artifact",
        bill_external_ids: ["24-1234"]
      }
      described_class.current_auto_include_context = payload
      expect(described_class.current_auto_include_context).to eq(payload)
    end

    it "is RE-INITIALIZED to nil after reset (CurrentAttributes contract)" do
      described_class.current_auto_include_context = {
        stage: "fetch-law",
        reason: "missing_artifact",
        bill_external_ids: ["24-9999"]
      }
      expect(described_class.current_auto_include_context).not_to be_nil

      described_class.reset

      expect(described_class.current_auto_include_context).to be_nil
    end

    it "is THREAD-ISOLATED — a value set on the main thread is not visible to a child thread" do
      described_class.current_auto_include_context = {a: 1}
      child_value = Thread.new { described_class.current_auto_include_context }.value
      expect(child_value).to be_nil
      # Reading from the child thread leaves the main thread's value alone.
      expect(described_class.current_auto_include_context).to eq({a: 1})
    end

    it "REPLACES the prior value wholesale on subsequent assignment (no merge)" do
      described_class.current_auto_include_context = {
        stage: "fetch-law",
        reason: "missing_artifact",
        bill_external_ids: ["24-1234"]
      }
      described_class.current_auto_include_context = {
        stage: "parse-sections",
        reason: "missing_artifact",
        bill_external_ids: ["24-5678"]
      }

      expect(described_class.current_auto_include_context).to eq(
        stage: "parse-sections",
        reason: "missing_artifact",
        bill_external_ids: ["24-5678"]
      )
    end

    it "clears to nil on explicit assignment of nil" do
      described_class.current_auto_include_context = {stage: "fetch-law", reason: "missing_artifact", bill_external_ids: Array.new(0, "")}
      described_class.current_auto_include_context = nil
      expect(described_class.current_auto_include_context).to be_nil
    end
  end

  describe "class shape" do
    it "is a subclass of ActiveSupport::CurrentAttributes (FINDING-1 mechanism)" do
      # This is the check that forces a real ActiveSupport::CurrentAttributes
      # subclass instead of a plain class. Rails clears CurrentAttributes between
      # units of work, and that automatic per-job reset is what the pipeline job
      # depends on.
      expect(described_class.ancestors).to include(ActiveSupport::CurrentAttributes)
    end
  end
end
