# frozen_string_literal: true

require "rails_helper"

# @lat: [[pipeline-stage-deps-transitive-closure#An unknown stage key]]
RSpec.describe Pipeline::StageDeps do
  describe ".transitive_closure" do
    it "returns the full ancestry for summarize-bill (Pitfall 1 — deepest chain)" do
      expected = %w[
        summarize-bill
        generate-diffs
        parse-sections
        extract-text
        fetch-law
        fetch-bills
        fetch-hearings
        clean-testimony
      ].to_set
      expect(described_class.transitive_closure(["summarize-bill"]).to_set).to eq(expected)
    end

    it "returns the four-node ancestry for parse-sections" do
      expected = %w[parse-sections extract-text fetch-law fetch-bills].to_set
      expect(described_class.transitive_closure(["parse-sections"]).to_set).to eq(expected)
    end

    it "returns just fetch-bills for fetch-bills (no upstream deps)" do
      expect(described_class.transitive_closure(["fetch-bills"]).to_set).to eq(%w[fetch-bills].to_set)
    end

    it "returns just fetch-law for fetch-law (run-level, no deps)" do
      expect(described_class.transitive_closure(["fetch-law"]).to_set).to eq(%w[fetch-law].to_set)
    end

    it "returns [] for empty input" do
      empty = [] #: Array[String]
      expect(described_class.transitive_closure(empty)).to eq([])
    end

    it "isolates unknown keys without raising (parser seam owns fail-closed)" do
      result = described_class.transitive_closure(["bogus-stage"])
      expect(result.to_set).to eq(%w[bogus-stage].to_set)
    end

    it "is idempotent on duplicate input" do
      expected = %w[parse-sections extract-text fetch-law fetch-bills].to_set
      expect(described_class.transitive_closure(["parse-sections", "parse-sections"]).to_set).to eq(expected)
    end

    it "unions deps across multiple seed keys" do
      # extract-text needs fetch-bills, and so does fetch-hearings. Asking for both
      # gives back both stages plus the single fetch-bills they share.
      expected = %w[extract-text fetch-hearings fetch-bills].to_set
      expect(described_class.transitive_closure(["extract-text", "fetch-hearings"]).to_set).to eq(expected)
    end

    it "terminates on the 8-node acyclic graph" do
      # Start from all 8 stages at once. Every stage is already marked as seen the
      # first time the walk reaches it, which is exactly where a sloppy loop would
      # spin forever. It has to finish.
      seed_keys = Pipeline::STAGE_DEPS.keys
      result = [] #: Array[String]
      expect {
        Timeout.timeout(2) { result = described_class.transitive_closure(seed_keys) }
      }.not_to raise_error
      expect(result.to_set).to eq(seed_keys.to_set)
    end
  end
end
