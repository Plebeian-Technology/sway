# frozen_string_literal: true

require "rails_helper"

module MarkupOpsSpecHelpers
  LEGEND = <<~LEGEND.strip
    EXPLANATION: CAPITALS indicate matter added to existing law.
    [Brackets] indicate matter deleted from existing law.
  LEGEND
end

RSpec.describe Legislation::MarkupOps do
  describe ".markup_fallback" do
    context "legend detection gate" do
      it "returns empty array when legend is absent" do
        text = "Section 1. [deleted text] ADDED CAPITAL TEXT HERE"
        expect(described_class.markup_fallback(text)).to eq([])
      end

      it "scans when legend is present with case-insensitive and whitespace tolerance" do
        text = <<~TXT
          explanation: capitals indicate matter added to existing law,
          [brackets] indicate matter deleted from existing law.

          Section 1. [old matter deleted] NEW MATTER ADDED HERE
        TXT
        ops = described_class.markup_fallback(text)
        expect(ops.size).to eq(2)
      end
    end

    context "exclusions" do
      it "excludes the legend sentence from strike and insert operations" do
        text = <<~TXT
          #{MarkupOpsSpecHelpers::LEGEND}

          Section 1. Normal law body.
        TXT
        ops = described_class.markup_fallback(text)
        expect(ops).to eq([])
      end

      it "excludes initial and subsequent enacting clauses" do
        text = <<~TXT
          #{MarkupOpsSpecHelpers::LEGEND}

          SECTION 1. BE IT ORDAINED BY THE MAYOR AND CITY COUNCIL OF BALTIMORE, That:
          [old statute language] NEW STATUTE LANGUAGE HERE
          SECTION 2. AND BE IT FURTHER ORDAINED, That this Ordinance takes effect immediately.
        TXT
        ops = described_class.markup_fallback(text)
        insert_texts = ops.select { |o| o[:operation] == :insert }.pluck(:anchor_text)
        expect(insert_texts).not_to include(a_string_including("BE IT ORDAINED"))
        expect(insert_texts).not_to include(a_string_including("AND BE IT FURTHER ORDAINED"))
        expect(insert_texts).to include("NEW STATUTE LANGUAGE HERE")
      end
    end

    context "bracket scanning (:strike)" do
      it "extracts bracketed runs with brackets stripped from anchor_text" do
        text = <<~TXT
          #{MarkupOpsSpecHelpers::LEGEND}
          An offender must register with the [Commissioner of Police.]
        TXT
        ops = described_class.markup_fallback(text)
        strike_op = ops.find { |o| o[:operation] == :strike }
        expect(strike_op).not_to be_nil
        expect(strike_op[:anchor_text]).to eq("Commissioner of Police.")
        expect(strike_op[:source]).to eq(:markup)
      end
    end

    context "capital scanning (:insert)" do
      it "extracts runs of 4 or more consecutive uppercase words" do
        text = <<~TXT
          #{MarkupOpsSpecHelpers::LEGEND}
          Subject to penalties for OPERATING WITHOUT A VALID BUSINESS LICENSE as defined.
        TXT
        ops = described_class.markup_fallback(text)
        insert_op = ops.find { |o| o[:operation] == :insert }
        expect(insert_op).not_to be_nil
        expect(insert_op[:anchor_text]).to eq("OPERATING WITHOUT A VALID BUSINESS LICENSE")
        expect(insert_op[:source]).to eq(:markup)
      end

      it "ignores capital runs of fewer than 4 words" do
        text = <<~TXT
          #{MarkupOpsSpecHelpers::LEGEND}
          CITY OF BALTIMORE.
          AN ORDINANCE CONCERNING the police commissioner.
        TXT
        ops = described_class.markup_fallback(text)
        expect(ops).to eq([])
      end

      it "ignores capital runs inside bracketed deletions" do
        text = <<~TXT
          #{MarkupOpsSpecHelpers::LEGEND}
          Repealing [SUBTITLE 61. ARSON OFFENDER REGISTRATION IN FULL] from Code.
        TXT
        ops = described_class.markup_fallback(text)
        expect(ops.pluck(:operation)).to eq([:strike])
      end
    end
  end

  describe ".reconstruct_before_and_after" do
    it "unwraps brackets and deletes capital runs in before_text; deletes brackets and keeps capital runs in after_text" do
      sample = <<~TXT
        #{MarkupOpsSpecHelpers::LEGEND}
        An offender must register with the [Commissioner of Police.] POLICE COMMISSIONER OF BALTIMORE CITY.
      TXT

      before_text, after_text = described_class.reconstruct_before_and_after(sample)

      expect(before_text).to include("Commissioner of Police.")
      expect(before_text).not_to include("POLICE COMMISSIONER OF BALTIMORE CITY")
      expect(before_text).not_to include("[Commissioner")

      expect(after_text).not_to include("Commissioner of Police.")
      expect(after_text).to include("POLICE COMMISSIONER OF BALTIMORE CITY")
    end

    it "preserves excluded clauses unchanged in both before and after texts" do
      sample = <<~TXT
        #{MarkupOpsSpecHelpers::LEGEND}
        SECTION 1. BE IT ORDAINED BY THE MAYOR AND CITY COUNCIL OF BALTIMORE, That:
        [deleted] ADDED FOUR CAPITAL WORDS
      TXT

      before_text, after_text = described_class.reconstruct_before_and_after(sample)

      expect(before_text).to include(MarkupOpsSpecHelpers::LEGEND)
      expect(after_text).to include(MarkupOpsSpecHelpers::LEGEND)
      expect(before_text).to include("BE IT ORDAINED BY THE MAYOR AND CITY COUNCIL OF BALTIMORE")
      expect(after_text).to include("BE IT ORDAINED BY THE MAYOR AND CITY COUNCIL OF BALTIMORE")
    end
  end
end
