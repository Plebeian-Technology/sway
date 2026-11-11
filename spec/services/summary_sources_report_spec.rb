# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
RSpec.describe SummarySourcesReport do
  let(:sway_locale) { create(:sway_locale, city: "Customcity", state: "Maryland", country: "United States") }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) do
    create(:bill, sway_locale: sway_locale, legislator: legislator, external_id: "HB1234", title: "An act concerning ledgers")
  end

  around do |example|
    Dir.mktmpdir do |tmp|
      with_app_config(:legislation, legislation_diffs_root: tmp) { example.run }
    end
  end

  describe ".call — what a run reads now" do
    it "reads the on-disk diff first and names it, with the bill's own text still counted beside it" do
      path = Legislation::Paths.diff_markdown_file(bill.external_id, sway_locale: bill.sway_locale.name)
      path.dirname.mkpath
      path.write("## Section 1\n- something added\n")
      bill.update!(extracted_text: "Section A. The Mayor shall do X.")
      bill.create_bill_llm_provisioning!(
        diff_content: {
          "target" => "charter",
          "stats" => {"sections_modified" => 2, "sections_referenced_only" => 1, "sections_not_found" => 3}
        }.to_json,
        diff_generated_at: Time.zone.parse("2026-08-27T20:02:07Z")
      )

      now = described_class.call(bill: bill).now

      expect(now.source_kind).to eq(:diff)
      expect(now.source_chars).to eq("## Section 1\n- something added\n".length)
      expect(now.source_truncated).to be(false)
      expect(now.extracted_text_chars).to eq("Section A. The Mayor shall do X.".length)
      expect(now.diff_target).to eq("charter")
      expect(now.diff_sections_modified).to eq(2)
      expect(now.diff_sections_referenced).to eq(1)
      expect(now.diff_sections_not_found).to eq(3)
      expect(now.diff_generated_at).to eq(Time.zone.parse("2026-08-27T20:02:07Z"))
    end

    it "falls back to the bill's own text when there is no diff on disk, and to nothing when there is no text either" do
      bill.update!(extracted_text: "Section A. The Mayor shall do X.")
      expect(described_class.call(bill: bill).now.source_kind).to eq(:extracted)

      bill.update!(extracted_text: nil)
      empty = described_class.call(bill: bill)
      expect(empty.now.source_kind).to eq(:none)
      expect(empty.now.source_chars).to eq(0)
      expect(empty.now.diff_target).to be_nil
      expect(empty.summary_generated_at).to be_nil
    end

    it "reports the cut the builder makes when the source is longer than the cap" do
      stub_app_config(:llm, llm_max_source_chars: 100)
      bill.update!(extracted_text: "x" * 250)

      now = described_class.call(bill: bill).now

      expect(now.source_truncated).to be(true)
      expect(now.source_cap).to eq(100)
      expect(now.source_reached_chars).to eq(100)
      expect(now.source_chars).to eq(250)
    end

    it "counts the law sections the model may cite and names the first few" do
      create(:bill_section_reference, bill: bill, key: "art_IV__sec_5", title: "Approval or veto of legislation.")
      create(:bill_section_reference, bill: bill, key: "art_IV__sec_6", title: nil)
      create(:bill_section_reference, bill: bill, key: "bad\nkey", title: "Unshowable")

      now = described_class.call(bill: bill).now

      expect(now.citation_keys_total).to eq(3)
      expect(now.citation_keys_offered).to eq(2)
      expect(now.citation_sample_titles).to eq(["Approval or veto of legislation.", "Unshowable"])
    end

    it "reads the newsrooms from the jurisdiction, and says whether the active provider can search them" do
      LlmBillSummarizationInstruction.create!(
        sway_locale: sway_locale,
        news_media_website_urls: ["https://www.thebanner.com/baltimore/", "https://baltimorebrew.com/", "http://insecure.example"]
      )
      article = create(:news_article, canonical_url: "https://www.thebanner.com/a", title: "Council weighs the bill")
      create(:bill_news_article, :approved, :with_text_version, bill: bill, news_article: article)
      bill.create_bill_llm_provisioning!(
        news_articles: [{"url" => "https://www.thebanner.com/a", "title" => "Council weighs\nthe bill"}],
        news_articles_fetched_at: Time.zone.parse("2026-09-01T12:00:00Z")
      )

      stub_app_config(:llm, llm_provider: "llamacpp")
      local = described_class.call(bill: bill).now
      expect(local.news_search_available).to be(false)
      expect(local.newsroom_domains).to eq(["thebanner.com/baltimore", "baltimorebrew.com"])
      expect(local.news_articles_total).to eq(1)
      expect(local.news_articles_offered).to eq(1)
      expect(local.news_articles).to eq([{title: "Council weighs the bill", host: "thebanner.com"}])
      expect(local.news_fetched_at).to eq(Time.zone.parse("2026-09-01T12:00:00Z"))

      stub_app_config(:llm, llm_provider: "claude")
      expect(described_class.call(bill: bill).now.news_search_available).to be(true)
    end

    it "carries the summary's own date, model and provider for the ledger to set the inputs against" do
      bill.create_bill_llm_provisioning!(
        llm_generated_at: Time.zone.parse("2026-07-21T17:24:50Z"), llm_model: "local", llm_provider: "llamacpp"
      )

      result = described_class.call(bill: bill)

      expect(result.summary_generated_at).to eq(Time.zone.parse("2026-07-21T17:24:50Z"))
      expect(result.summary_model).to eq("local")
      expect(result.summary_provider).to eq("llamacpp")
    end

    it "treats a diff payload that does not parse as no payload rather than failing the page" do
      bill.create_bill_llm_provisioning!(diff_content: "{not json")

      now = described_class.call(bill: bill).now

      expect(now.diff_target).to be_nil
      expect(now.diff_sections_modified).to be_nil
      expect(now.diff_sections_not_found).to be_nil
    end
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  describe ".call — what the recorded run read" do
    it "reports no recorded run when nothing has been written for the bill" do
      expect(described_class.call(bill: bill).read).to be_nil
    end

    it "reads the stored facts rather than recomputing them, so a later re-extraction cannot move them" do
      create(
        :bill_summary_prompt_snapshot,
        bill: bill,
        built_at: Time.zone.parse("2026-09-01T09:00:00Z"),
        llm_model: "claude-opus-4-6", llm_provider: "claude",
        facts: {
          "source_kind" => "extracted", "source_chars" => 40, "source_cap" => 45_000,
          "source_reached_chars" => 40, "source_truncated" => false, "extracted_text_chars" => 40,
          "diff_target" => "charter", "diff_sections_modified" => 2, "diff_sections_referenced" => 1,
          "diff_sections_not_found" => 3, "diff_generated_at" => "2026-08-27T20:02:07Z",
          "citation_keys_offered" => 4, "citation_keys_total" => 5, "citation_sample_titles" => ["One"],
          "news_search_available" => true, "news_fetched_at" => "2026-09-01T08:00:00Z",
          "newsroom_domains" => ["thebanner.com"], "news_articles_offered" => 1, "news_articles_total" => 2,
          "news_articles" => [{"title" => "Council weighs the bill", "host" => "thebanner.com"}]
        }
      )
      bill.update!(extracted_text: "x" * 9_000)

      read = described_class.call(bill: bill).read #: SummarySourcesReport::Read

      expect(read.built_at).to eq(Time.zone.parse("2026-09-01T09:00:00Z"))
      expect(read.llm_model).to eq("claude-opus-4-6")
      expect(read.llm_provider).to eq("claude")
      expect(read.record.source_kind).to eq(:extracted)
      expect(read.record.extracted_text_chars).to eq(40)
      expect(read.record.diff_sections_not_found).to eq(3)
      expect(read.record.news_search_available).to be(true)
      expect(read.record.news_fetched_at).to eq(Time.zone.parse("2026-09-01T08:00:00Z"))
      expect(read.record.news_articles).to eq([{title: "Council weighs the bill", host: "thebanner.com"}])
      expect(described_class.call(bill: bill).now.extracted_text_chars).to eq(9_000)
    end

    it "fills a fact the stored hash is missing rather than leaving the key off the record" do
      create(:bill_summary_prompt_snapshot, bill: bill, facts: {"source_kind" => "diff", "source_chars" => 12})

      record = described_class.call(bill: bill).read.record

      expect(record.source_kind).to eq(:diff)
      expect(record.source_chars).to eq(12)
      expect(record.source_cap).to eq(0)
      expect(record.source_reached_chars).to eq(0)
      expect(record.source_truncated).to be(false)
      expect(record.citation_sample_titles).to eq([])
      expect(record.newsroom_domains).to eq([])
      expect(record.news_articles).to eq([])
      expect(record.diff_generated_at).to be_nil
      expect(record.to_h.keys).to match_array(described_class.call(bill: bill).now.to_h.keys)
    end

    it "treats stored facts that are not a hash — null, a string, an array — as no facts at all" do
      snapshot = create(:bill_summary_prompt_snapshot, bill: bill)

      [nil, "null", '"a string"', '["not a hash"]'].each do |stored|
        BillSummaryPromptSnapshot
          .where(id: snapshot.id)
          .update_all(BillSummaryPromptSnapshot.sanitize_sql_array(["facts = ?", stored]))

        read = described_class.call(bill: bill.reload).read #: SummarySourcesReport::Read
        record = read.record

        expect(read.built_at).not_to be_nil
        expect(record.source_kind).to eq(:none)
        expect(record.source_chars).to eq(0)
        expect(record.source_cap).to eq(0)
        expect(record.source_reached_chars).to eq(0)
        expect(record.source_truncated).to be(false)
        expect(record.diff_target).to be_nil
        expect(record.diff_generated_at).to be_nil
        expect(record.citation_sample_titles).to eq([])
        expect(record.newsroom_domains).to eq([])
        expect(record.news_articles).to eq([])
        expect(record.to_h.keys).to match_array(described_class.call(bill: bill).now.to_h.keys)
      end
    end

    it "ships every ledger key even when the stored facts are empty, so the panel reads none of them as absent" do
      create(:bill_summary_prompt_snapshot, bill: bill, facts: {})

      raw = SummarySourcesResource.new(described_class.call(bill: bill)).serializable_hash #: Hash[Symbol, untyped]
      read = raw.transform_keys(&:to_s)["read"] #: Hash[String, untyped]

      expect(read.keys).to include("source_kind", "source_chars", "news_articles", "built_at", "llm_provider")
      expect(read["source_kind"]).to eq("none")
      expect(read.values_at("source_chars", "source_cap", "extracted_text_chars")).to eq([0, 0, 0])
      expect(read["news_articles"]).to eq([])
    end

    it "reads back every fact the run writes, so the two halves of the record cannot drift apart" do
      LlmBillSummarizationInstruction.create!(
        sway_locale: sway_locale, news_media_website_urls: ["https://www.thebanner.com/baltimore/"]
      )
      bill.update!(extracted_text: "Section A. The Mayor shall do X.")
      create(:bill_section_reference, bill: bill, key: "art_IV__sec_5", title: "Approval or veto of legislation.")
      bill.create_bill_llm_provisioning!(
        diff_content: {"target" => "charter", "stats" => {"sections_modified" => 2, "sections_referenced_only" => 1, "sections_not_found" => 3}}.to_json,
        diff_generated_at: Time.zone.parse("2026-08-27T20:02:07Z"),
        news_articles: [{"url" => "https://www.thebanner.com/a", "title" => "Council weighs the bill"}],
        news_articles_fetched_at: Time.zone.parse("2026-09-01T12:00:00Z")
      )
      written = described_class.record(bill: bill)

      create(
        :bill_summary_prompt_snapshot,
        bill: bill, facts: SummarySourcesRecordResource.new(written).serializable_hash
      )

      expect(described_class.call(bill: bill.reload).read.record).to eq(written)
    end
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  describe ".record" do
    it "builds the record from counts a caller already has, without asking the builder again" do
      bill.update!(extracted_text: "Section A. The Mayor shall do X.")
      sources = BillSummaryPromptBuilder.new(bill).sources
      expect(BillSummaryPromptBuilder).not_to receive(:new)

      record = described_class.record(bill: bill, sources: sources)

      expect(record.source_kind).to eq(:extracted)
      expect(record.source_chars).to eq("Section A. The Mayor shall do X.".length)
    end
  end
end
