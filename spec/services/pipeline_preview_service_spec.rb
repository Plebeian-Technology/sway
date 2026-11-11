require "rails_helper"

# PipelinePreviewService is plain Ruby, replacing a client for the retired
# Python service.
# compute_will_run now asks StageDeps.transitive_closure instead of
# guessing a stage-list prefix.
RSpec.describe PipelinePreviewService do
  # The old signature took kind:, target_bill_external_id: and refresh: to
  # match the Python service, but none changed which stages ran. The
  # service now takes a single stages: argument.
  describe "#fetch" do
    it "returns a PreviewResponse Hash with DAG-ordered stages_will_run + auto-include set" do
      result = described_class.fetch(stages: ["parse-sections"])
      expect(result).to include(
        "stages_requested" => ["parse-sections"],
        "stages_will_run" => ["fetch-bills", "fetch-law", "extract-text", "parse-sections"],
        "stages_auto_included" => ["fetch-bills", "fetch-law", "extract-text"],
        "confirmation_required" => true
      )
      expect(result["confirmation_message"]).to include(
        "fetch-bills, fetch-law, extract-text"
      )
    end

    it "returns confirmation_required=false when no auto-include is needed (only fetch-bills selected)" do
      result = described_class.fetch(stages: ["fetch-bills"])
      expect(result).to include(
        "stages_requested" => ["fetch-bills"],
        "stages_will_run" => ["fetch-bills"],
        "confirmation_required" => false,
        "confirmation_message" => nil,
        "stages_auto_included" => [] #: Array[untyped]
      )
    end

    it "returns nil when stages array is empty (short-circuit per UI-SPEC §Display rules)" do
      result = described_class.fetch(
        stages: [] #: Array[untyped]
      )
      expect(result).to be_nil
    end

    it "returns nil and logs a warning when an unknown stage is requested" do
      expect(Rails.logger).to receive(:warn).with(/PipelinePreviewService.*bogus-stage/)
      result = described_class.fetch(stages: ["bogus-stage"])
      expect(result).to be_nil
    end

    it "returns only the locked PREVIEW_RESPONSE_KEYS (with additive prereq_violations) and includes prereq_violations" do
      result = described_class.fetch(stages: ["parse-sections"])
      # prereq_violations is a NEW key; nothing was taken away.
      expect(result.keys).to include(*described_class::PREVIEW_RESPONSE_KEYS)
      expect(result.keys).to include("prereq_violations")
    end

    it "does NOT auto-include downstream stages when only an early stage is selected" do
      result = described_class.fetch(stages: ["fetch-bills", "fetch-law"])
      # The operator picked stages up to fetch-law, so the chain stops there.
      expect(result["stages_will_run"]).to match_array(["fetch-bills", "fetch-law"])
      expect(result["stages_auto_included"]).to eq([])
    end
  end

  describe ".fetch (class method)" do
    it "delegates to a fresh instance" do
      result = described_class.fetch(stages: ["parse-sections"])
      expect(result).to be_a(Hash)
      expect(result["stages_requested"]).to eq(["parse-sections"])
    end
  end

  # How the stage chain is worked out: STAGE_DEPS, which knows which artifacts
  # each stage needs, replaced the old "take a prefix of the stage list" guess.
  describe "transitive closure semantics" do
    it "auto-includes the FULL transitive chain for summarize-bill (including fetch-hearings and clean-testimony)" do
      result = described_class.fetch(stages: ["summarize-bill"])
      # The STAGE_DEPS chain for summarize-bill: summarize-bill ->
      # generate-diffs -> parse-sections -> extract-text -> fetch-bills;
      # parse-sections -> fetch-law; and summarize-bill -> fetch-hearings ->
      # clean-testimony.
      expect(result["stages_will_run"]).to match_array(
        ["fetch-bills", "fetch-law", "extract-text", "parse-sections", "generate-diffs", "fetch-hearings", "clean-testimony", "summarize-bill"]
      )
      expect(result["stages_auto_included"]).to match_array(
        ["fetch-bills", "fetch-law", "extract-text", "parse-sections", "generate-diffs", "fetch-hearings", "clean-testimony"]
      )
      expect(result["confirmation_required"]).to be(true)
    end

    it "auto-includes only the strict prereqs of parse-sections (no downstream stages)" do
      result = described_class.fetch(stages: ["parse-sections"])
      expect(result["stages_will_run"]).to match_array(
        ["fetch-bills", "fetch-law", "extract-text", "parse-sections"]
      )
      expect(result["stages_auto_included"]).to match_array(
        ["fetch-bills", "fetch-law", "extract-text"]
      )
      # Later stages (generate-diffs, summarize-bill) are NOT added on their own.
      expect(result["stages_will_run"]).not_to include("generate-diffs")
      expect(result["stages_will_run"]).not_to include("summarize-bill")
    end

    it "fetch-hearings only pulls in its own dep (fetch-bills) — does NOT pull the parse-sections branch" do
      result = described_class.fetch(stages: ["fetch-hearings"])
      # In STAGE_DEPS, fetch-hearings depends on fetch-bills and nothing else.
      expect(result["stages_will_run"]).to match_array(["fetch-bills", "fetch-hearings"])
      expect(result["stages_auto_included"]).to eq(["fetch-bills"])
      # The old prefix-based guess would have pulled in fetch-law, extract-text,
      # parse-sections and generate-diffs here. Following the real dependencies
      # does NOT.
      expect(result["stages_will_run"]).not_to include("fetch-law")
      expect(result["stages_will_run"]).not_to include("parse-sections")
      expect(result["stages_will_run"]).not_to include("generate-diffs")
    end

    it "intersects closure with batched artifact-presence when dma=true" do
      # When every bill in scope already has the artifact a chain stage would
      # produce, that stage is left OUT of the will_run set.
      bills_relation = Bill.none
      allow(Pipeline::ArtifactPresence).to receive(:batch_for).with(bills: bills_relation).and_return(
        {
          "bill-A" => {
            "fetch-bills" => true,
            "extract-text" => true,
            "parse-sections" => false,
            "generate-diffs" => false,
            "fetch-hearings" => false,
            "summarize-bill" => false
          }
        }
      )
      result = described_class.fetch(
        stages: ["parse-sections"],
        download_missing_assets: true,
        bills: bills_relation
      )
      # fetch-bills and extract-text already exist for every bill in scope,
      # so they drop out of will_run. fetch-law stays (once per run).
      # parse-sections is what the operator ticked, so it always runs.
      expect(result["stages_will_run"]).to include("parse-sections")
      expect(result["stages_will_run"]).not_to include("fetch-bills")
      expect(result["stages_will_run"]).not_to include("extract-text")
      expect(result["stages_auto_included"]).not_to include("fetch-bills")
      expect(result["stages_auto_included"]).not_to include("extract-text")
    end
  end

  # The prereq_violations field, which feeds the warning alert in the UI.
  describe "prereq_violations field" do
    it "emits prereq_violations when dma=false and bills are missing prerequisite artifacts" do
      bills_relation = Bill.none
      allow(Pipeline::ArtifactPresence).to receive(:batch_for).with(bills: bills_relation).and_return(
        {
          "bill-A" => {
            "fetch-bills" => true,
            "extract-text" => false,  # missing, and parse-sections needs it
            "parse-sections" => false,
            "generate-diffs" => false,
            "fetch-hearings" => false,
            "summarize-bill" => false
          },
          "bill-B" => {
            "fetch-bills" => true,
            "extract-text" => false,
            "parse-sections" => false,
            "generate-diffs" => false,
            "fetch-hearings" => false,
            "summarize-bill" => false
          }
        }
      )
      result = described_class.fetch(
        stages: ["parse-sections"],
        download_missing_assets: false,
        bills: bills_relation
      )
      expect(result["prereq_violations"]).to be_an(Array)
      violation = result["prereq_violations"].find { |v| v["prerequisite"] == "extract-text" }
      expect(violation).to include(
        "stage" => "parse-sections",
        "prerequisite" => "extract-text",
        "missing_artifact" => "extracted_text",
        "bill_count" => 2
      )
    end

    it "returns empty prereq_violations when dma=true (auto-include handles it)" do
      bills_relation = Bill.none
      allow(Pipeline::ArtifactPresence).to receive(:batch_for).with(bills: bills_relation).and_return(
        {
          "bill-A" => {
            "fetch-bills" => false,
            "extract-text" => false,
            "parse-sections" => false,
            "generate-diffs" => false,
            "fetch-hearings" => false,
            "summarize-bill" => false
          }
        }
      )
      result = described_class.fetch(
        stages: ["parse-sections"],
        download_missing_assets: true,
        bills: bills_relation
      )
      expect(result["prereq_violations"]).to eq([])
    end

    it "returns empty prereq_violations when dma=false but all prereqs are satisfied" do
      bills_relation = Bill.none
      allow(Pipeline::ArtifactPresence).to receive(:batch_for).with(bills: bills_relation).and_return(
        {
          "bill-A" => {
            "fetch-bills" => true,
            "extract-text" => true,
            "parse-sections" => true,
            "generate-diffs" => true,
            "fetch-hearings" => true,
            "summarize-bill" => true
          }
        }
      )
      result = described_class.fetch(
        stages: ["parse-sections"],
        download_missing_assets: false,
        bills: bills_relation
      )
      expect(result["prereq_violations"]).to eq([])
    end
  end

  # A speed rule: batch_for must be called AT MOST ONCE per fetch. With 166
  # bills that turns roughly 1000 separate database hits into about 3.
  describe "batched artifact-presence consumption (FINDING-3)" do
    it "invokes Pipeline::ArtifactPresence.batch_for AT MOST ONCE per fetch call" do
      bills_relation = Bill.none
      expect(Pipeline::ArtifactPresence).to receive(:batch_for).once.and_call_original
      described_class.fetch(
        stages: ["parse-sections"],
        download_missing_assets: false,
        bills: bills_relation
      )
    end

    it "tolerates an empty bills relation (Bill.none) without crashing" do
      result = described_class.fetch(
        stages: ["parse-sections"],
        download_missing_assets: false,
        bills: Bill.none
      )
      expect(result).to be_a(Hash)
      expect(result["prereq_violations"]).to eq([])
    end
  end
end
