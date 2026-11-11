# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")
require Rails.root.join("db", "seeds", "models", "seed_llm_bill_summarization_instruction")

RSpec.describe SeedLlmBillSummarizationInstruction do
  before do
    SeedSwayLocale.run
  end

  let(:locales) { SwayLocale.all.to_a }

  describe ".run" do
    it "seeds exactly one instruction per declared sway locale" do
      expect do
        described_class.run(locales)
      end.to change(LlmBillSummarizationInstruction, :count).by(3)

      expect(LlmBillSummarizationInstruction.count).to eq(3)
    end

    it "is idempotent and does not create duplicate rows on repeated runs" do
      described_class.run(locales)

      expect do
        described_class.run(locales)
      end.not_to change(LlmBillSummarizationInstruction, :count)

      expect(LlmBillSummarizationInstruction.count).to eq(3)
    end

    it "preserves out-of-band edits via Seedable" do
      described_class.run(locales)

      baltimore_locale = SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") || raise("missing locale")
      instruction = baltimore_locale.llm_bill_summarization_instruction
      instruction.update!(legislative_body_makeup: "Custom edited body makeup.")

      # Re-running seeds without force preserves the custom edit
      described_class.run(locales, force: false)
      expect(instruction.reload.legislative_body_makeup).to eq("Custom edited body makeup.")

      # Re-running with force: true overwrites the edit
      described_class.run(locales, force: true)
      expect(instruction.reload.legislative_body_makeup).not_to eq("Custom edited body makeup.")
      expect(instruction.reload.legislative_body_makeup).to include("A 15-member legislative body")
    end

    it "does not include chamber_label in any seeded description" do
      instructions = described_class.run(locales)
      expect(instructions).not_to be_empty

      instructions.each do |instruction|
        rules = SwayLocale::JurisdictionRulesRegistry.fetch(instruction.sway_locale.name)

        expect(instruction).to be_present
        expect(instruction.legislative_body_makeup).not_to include(rules.chamber_label)
      end
    end

    it "does not include the word 'Congress' anywhere in the US Congress description" do
      described_class.run(locales)

      congress_locale = SwayLocale.resolve_by_computed_name("congress-congress-united_states") || raise("missing locale")
      instruction = congress_locale.reload.llm_bill_summarization_instruction

      expect(instruction).to be_present
      expect(instruction.legislative_body_makeup).not_to match(/\bcongress\b/i)
      expect(instruction.legislative_body_makeup).to include("session")
    end

    it "seeds the expected news media website URLs for each sway locale" do
      described_class.run(locales)

      baltimore = SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") || raise("missing locale")
      maryland = SwayLocale.resolve_by_computed_name("maryland-maryland-united_states") || raise("missing locale")
      congress = SwayLocale.resolve_by_computed_name("congress-congress-united_states") || raise("missing locale")

      expect(baltimore.llm_bill_summarization_instruction.news_media_website_urls.length).to eq(11)
      expect(maryland.llm_bill_summarization_instruction.news_media_website_urls.length).to eq(3)
      expect(congress.llm_bill_summarization_instruction.news_media_website_urls.length).to eq(4)

      all_urls = [baltimore, maryland, congress].flat_map do |loc|
        loc.llm_bill_summarization_instruction.news_media_website_urls
      end

      all_urls.each do |url|
        uri = URI.parse(url)
        expect(uri.scheme).to eq("https")
        expect(uri.host).to be_present
      end
    end

    it "preserves out-of-band edits to news media website URLs via Seedable" do
      described_class.run(locales)

      baltimore = SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") || raise("missing locale")
      instruction = baltimore.llm_bill_summarization_instruction
      instruction.update!(news_media_website_urls: ["https://custom-news.org/"])

      described_class.run(locales, force: false)
      expect(instruction.reload.news_media_website_urls).to eq(["https://custom-news.org/"])

      described_class.run(locales, force: true)
      expect(instruction.reload.news_media_website_urls.length).to eq(11)
    end

    it "seeds jurisdiction-authentic worked examples for each sway locale" do
      described_class.run(locales)

      baltimore = SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") || raise("missing locale")
      maryland = SwayLocale.resolve_by_computed_name("maryland-maryland-united_states") || raise("missing locale")
      congress = SwayLocale.resolve_by_computed_name("congress-congress-united_states") || raise("missing locale")

      balt_example = baltimore.llm_bill_summarization_instruction.worked_example
      md_example = maryland.llm_bill_summarization_instruction.worked_example
      cong_example = congress.llm_bill_summarization_instruction.worked_example

      expect(balt_example).to include("Baltimore City Code", "CB 23-0312")
      expect(balt_example).not_to include("Annotated Code of Maryland")
      expect(balt_example).not_to include("United States Code")

      expect(md_example).to include("Annotated Code of Maryland", "HB 452")
      expect(md_example).not_to include("Baltimore City Code")
      expect(md_example).not_to include("CB 23-0312")

      expect(cong_example).to include("United States Code", "H.R. 2030")
      expect(cong_example).not_to include("Baltimore City Code")
      expect(cong_example).not_to include("CB 23-0312")
    end

    it "preserves out-of-band edits to worked_example via Seedable" do
      described_class.run(locales)

      baltimore = SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") || raise("missing locale")
      instruction = baltimore.llm_bill_summarization_instruction
      instruction.update!(worked_example: "Custom worked example text.")

      described_class.run(locales, force: false)
      expect(instruction.reload.worked_example).to eq("Custom worked example text.")

      described_class.run(locales, force: true)
      expect(instruction.reload.worked_example).not_to eq("Custom worked example text.")
      expect(instruction.reload.worked_example).to include("CB 23-0312")
    end
  end
end
