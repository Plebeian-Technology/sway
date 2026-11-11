# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: llm_bill_summarization_instructions
# Database name: primary
#
#  id                      :integer          not null, primary key
#  last_seeded_at          :datetime
#  legislative_body_makeup :text
#  news_media_website_urls :json             not null
#  worked_example          :text
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  sway_locale_id          :integer          not null
#
# Indexes
#
#  index_llm_bill_summarization_instructions_on_sway_locale_id  (sway_locale_id) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
RSpec.describe LlmBillSummarizationInstruction, type: :model do
  let(:baltimore) { create(:sway_locale, :baltimore) }

  describe "validations" do
    it "is valid with valid attributes" do
      instruction = build(:llm_bill_summarization_instruction, sway_locale: baltimore)
      expect(instruction).to be_valid
    end

    it "validates uniqueness of sway_locale_id at model level" do
      create(:llm_bill_summarization_instruction, sway_locale: baltimore)
      duplicate = build(:llm_bill_summarization_instruction, sway_locale: baltimore)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:sway_locale_id]).to include("has already been taken")
    end

    it "enforces uniqueness of sway_locale_id via database unique index" do
      create(:llm_bill_summarization_instruction, sway_locale: baltimore)

      expect do
        build(:llm_bill_summarization_instruction, sway_locale: baltimore).save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "associations" do
    it "belongs to a sway_locale" do
      instruction = create(:llm_bill_summarization_instruction, sway_locale: baltimore)
      expect(instruction.sway_locale).to eq(baltimore)
    end

    it "is accessible from sway_locale via has_one association" do
      instruction = create(:llm_bill_summarization_instruction, sway_locale: baltimore)
      expect(baltimore.reload.llm_bill_summarization_instruction).to eq(instruction)
    end

    it "is destroyed when the associated sway_locale is destroyed" do
      instruction = create(:llm_bill_summarization_instruction, sway_locale: baltimore)
      expect do
        baltimore.destroy
      end.to change { described_class.exists?(instruction.id) }.from(true).to(false)
    end
  end

  # @lat: [[news-source-configuration#News source configuration contract]]
  describe "#allowed_domains and #news_sources" do
    it "reads from authoritative locale document and derives allowed_domains" do
      instruction = build(
        :llm_bill_summarization_instruction,
        sway_locale: baltimore,
        news_media_website_urls: ["https://stale.news.org/"]
      )

      expect(instruction.news_sources.length).to eq(11)
      expect(instruction.news_sources.first["url"]).to eq("https://www.thebanner.com/baltimore/")
      expect(instruction.allowed_domains).to include("thebanner.com/baltimore", "wypr.org")
      expect(instruction.allowed_domains).not_to include("wbaltv.com")
      expect(instruction.allowed_domains).not_to include("stale.news.org")
    end

    it "falls back to news_media_website_urls when sway_locale document is absent" do
      instruction = build(
        :llm_bill_summarization_instruction,
        sway_locale: nil,
        news_media_website_urls: [
          "https://www.thebanner.com/baltimore/",
          "https://www.wypr.org/",
          "http://insecure.example.com"
        ]
      )

      expect(instruction.news_sources).to eq([
        {"url" => "https://www.thebanner.com/baltimore/", "path_policy" => "search_hint"},
        {"url" => "https://www.wypr.org/", "path_policy" => "search_hint"},
        {"url" => "http://insecure.example.com", "path_policy" => "search_hint"}
      ])
      expect(instruction.allowed_domains).to eq(["thebanner.com/baltimore", "wypr.org"])
    end

    it "returns an empty array when news sources are empty" do
      annapolis = create(:sway_locale, city: "annapolis", state: "maryland", country: "united_states")
      instruction = build(:llm_bill_summarization_instruction, sway_locale: annapolis)
      expect(instruction.news_sources).to eq([])
      expect(instruction.allowed_domains).to eq([])
    end

    it "provides source_config_digest matching locale document" do
      instruction = build(:llm_bill_summarization_instruction, sway_locale: baltimore)
      doc = SwayLocale::DocumentReader.current_for(baltimore.name)
      expect(instruction.source_config_digest).to eq(doc.source_config_digest)
    end

    it "normalizes default port 443 and strips custom ports in fallback news_media_website_urls" do
      instruction = build(
        :llm_bill_summarization_instruction,
        sway_locale: nil,
        news_media_website_urls: [
          "https://www.thebanner.com:443/baltimore/",
          "https://www.wypr.org:8443/news"
        ]
      )

      expect(instruction.news_sources.first["url"]).to eq("https://www.thebanner.com/baltimore/")
      expect(instruction.allowed_domains).to eq(["thebanner.com/baltimore", "wypr.org/news"])
    end
  end

  describe "attributes" do
    it "persists and reads worked_example text" do
      instruction = create(
        :llm_bill_summarization_instruction,
        sway_locale: baltimore,
        worked_example: "For a hypothetical Baltimore City Council ordinance..."
      )

      expect(instruction.reload.worked_example).to eq("For a hypothetical Baltimore City Council ordinance...")
    end
  end
end
