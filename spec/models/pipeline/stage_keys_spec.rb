# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pipeline::StageKeys do
  describe ".to_symbol" do
    it "maps 'summarize-bill' to :summarize" do
      expect(described_class.to_symbol("summarize-bill")).to eq(:summarize)
    end

    it "maps 'fetch-bills' to :fetch_bills" do
      expect(described_class.to_symbol("fetch-bills")).to eq(:fetch_bills)
    end

    it "maps 'fetch-law' to :fetch_law" do
      expect(described_class.to_symbol("fetch-law")).to eq(:fetch_law)
    end

    it "maps 'extract-text' to :extract_text" do
      expect(described_class.to_symbol("extract-text")).to eq(:extract_text)
    end

    it "maps 'parse-sections' to :parse_sections" do
      expect(described_class.to_symbol("parse-sections")).to eq(:parse_sections)
    end

    it "maps 'generate-diffs' to :generate_diffs" do
      expect(described_class.to_symbol("generate-diffs")).to eq(:generate_diffs)
    end

    it "maps 'fetch-hearings' to :fetch_hearings" do
      expect(described_class.to_symbol("fetch-hearings")).to eq(:fetch_hearings)
    end

    it "raises KeyError when given an unknown stage key (fail-closed)" do
      expect { described_class.to_symbol("bogus-stage") }.to raise_error(KeyError)
    end

    it "coerces symbol-like input to string before lookup" do
      expect(described_class.to_symbol(:"summarize-bill")).to eq(:summarize)
    end
  end

  describe ".to_key" do
    it "maps :summarize to 'summarize-bill'" do
      expect(described_class.to_key(:summarize)).to eq("summarize-bill")
    end

    it "maps :fetch_bills to 'fetch-bills'" do
      expect(described_class.to_key(:fetch_bills)).to eq("fetch-bills")
    end

    it "maps :fetch_law to 'fetch-law'" do
      expect(described_class.to_key(:fetch_law)).to eq("fetch-law")
    end

    it "raises KeyError when given an unknown stage symbol (fail-closed)" do
      expect { described_class.to_key(:bogus) }.to raise_error(KeyError)
    end
  end

  describe "KEY_TO_SYMBOL" do
    it "is frozen" do
      expect(described_class::KEY_TO_SYMBOL).to be_frozen
    end

    it "has the 8 expected hyphenated keys in alphabetical sort order" do
      expect(described_class::KEY_TO_SYMBOL.keys.sort).to eq(
        ["clean-testimony", "extract-text", "fetch-bills", "fetch-hearings", "fetch-law", "generate-diffs",
          "parse-sections", "summarize-bill"]
      )
    end
  end

  describe "SYMBOL_TO_KEY" do
    it "is frozen" do
      expect(described_class::SYMBOL_TO_KEY).to be_frozen
    end

    it "has the 8 expected stage symbols in alphabetical sort order" do
      expect(described_class::SYMBOL_TO_KEY.keys.sort).to eq(
        [:clean_testimony, :extract_text, :fetch_bills, :fetch_hearings, :fetch_law, :generate_diffs,
          :parse_sections, :summarize]
      )
    end

    it "matches RunLegislationPipelineJob::DAG_ORDER (boot-time parity)" do
      expect(described_class::SYMBOL_TO_KEY.keys.sort).to eq(RunLegislationPipelineJob::DAG_ORDER.sort)
    end
  end
end
