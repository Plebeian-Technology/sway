# frozen_string_literal: true

require "rails_helper"

# @lat: [[news-article-evidence#Grounding decisions]]
RSpec.describe NewsClaimGroundingService do
  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale, link: "https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345") }
  let(:other_bill) { create(:bill, sway_locale: sway_locale) }

  let(:news_article) do
    create(
      :news_article,
      canonical_url: "https://baltimoresun.com/news/council-bill-density",
      title: "Council Approves Zoning Density Bill 14-0",
      outlet_name: "The Baltimore Sun",
      author_name: "Jane Reporter"
    )
  end

  let(:article_text) do
    "The Baltimore City Council voted unanimously 14-0 on Monday night to approve the zoning density bill. " \
      "Sponsor Councilman Mark Conway noted that the measure will create 500 affordable units across District 4. " \
      "Opponents had raised traffic concerns, but no councilmember voted against the final measure."
  end

  let(:text_version) do
    create(
      :news_article_text_version,
      :extracted,
      news_article: news_article,
      text: article_text
    )
  end

  let(:bill_news_article) do
    create(
      :bill_news_article,
      :approved,
      bill: bill,
      news_article: news_article,
      current_text_version: text_version,
      review_version: 1
    )
  end

  let(:snapshot) do
    NewsArticleSourceSnapshotService.capture!(
      bill: bill,
      purpose: "summary",
      run_receipt: "test_receipt_m14",
      sources: [bill_news_article]
    )
  end

  let(:verbatim_excerpt) { "The Baltimore City Council voted unanimously 14-0 on Monday night to approve the zoning density bill." }
  let(:supported_claim) { "The City Council voted unanimously 14-0 to approve the zoning density bill." }
  let(:summary_prose) do
    "According to [The Baltimore Sun](https://baltimoresun.com/news/council-bill-density), " \
      "The City Council voted unanimously 14-0 to approve the zoning density bill. Official details at [Legistar](https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345)."
  end

  let(:mock_route) do
    Llm::RouteResolver::Route.new(provider: :claude, api_model: "claude-3-5-haiku-latest")
  end

  let(:mock_adapter) { instance_double(Llm::ClaudeAdapter) }

  before do
    allow(Llm::RouteResolver).to receive(:resolve).with(purpose: :summary).and_return(mock_route)
    allow(Llm::Client).to receive(:build).with(provider: :claude).and_return(mock_adapter)
  end

  describe "Phase 1: Deterministic fast-fail validation" do
    it "fast-fails with unsupported verdict when evidence excerpt does not appear verbatim in text version" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => "Tampered excerpt that never appears in the article text at all.",
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.phase).to eq(:deterministic)
      expect(result.errors.first).to match(/verbatim/i)
    end

    it "fast-fails with unsupported verdict when bill news article is unapproved" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      bill_news_article.update_columns(approved: false, updated_at: Time.current)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.claim_assessments.first.phase).to eq(:deterministic)
      expect(result.errors.first).to match(/approval/i)
    end

    it "fast-fails with unsupported verdict on cross-bill article mismatch" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      other_bna = create(
        :bill_news_article,
        :approved,
        bill: other_bill,
        news_article: news_article,
        current_text_version: text_version
      )

      source_uses = [
        {
          "bill_news_article_id" => other_bna.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors.first).to match(/belong to bill/i)
    end

    it "fast-fails with unsupported verdict on text version mismatch" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      other_tv = create(
        :news_article_text_version,
        :extracted,
        news_article: news_article,
        text: "Different version of the text that also has The Baltimore City Council voted unanimously 14-0 on Monday night to approve the zoning density bill."
      )
      bill_news_article.update_columns(current_text_version_id: other_tv.id, updated_at: Time.current)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id, # Stale text version!
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors.first).to match(/current text version/i)
    end

    it "fast-fails with unsupported verdict on review version mismatch against snapshot" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      # Ensure snapshot is captured with review_version 1
      active_snapshot = snapshot
      # Increment review_version on association after snapshot was taken
      bill_news_article.update_columns(review_version: 2, updated_at: Time.current)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        snapshot: active_snapshot,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors.first).to match(/review version mismatch/i)
    end

    it "semantically grounds visible news citation in prose to an approved bill news article when source_uses is empty" do
      expect(mock_adapter).to receive(:generate_news_claim_grounding).and_return(
        {"verdict" => "supported", "reason" => "Prose claim matches article."}
      )
      bill_news_article

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: [],
        news_usage: "cited"
      )

      expect(result).to be_valid
      expect(result).to be_supported
      expect(result.errors).to be_empty
    end

    it "rejects unmanifested visible news citation in prose when semantic grounding returns unsupported" do
      expect(mock_adapter).to receive(:generate_news_claim_grounding).and_return(
        {"verdict" => "unsupported", "reason" => "Prose claim contradicts article."}
      )
      bill_news_article

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: [],
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors).to include("Prose claim contradicts article.")
    end

    it "fast-fails deterministically when visible news citation in prose does not belong to an approved article for the bill" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: [],
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors.first).to match(/does not belong to an approved news article/i)
    end

    it "fast-fails deterministically when source_uses is empty and snapshot entry has nil or mismatched text_version_id" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)
      active_snapshot = snapshot
      allow(active_snapshot).to receive(:captured_source_entries).and_return(
        [{"bill_news_article_id" => bill_news_article.id, "text_version_id" => nil, "review_version" => 1}]
      )

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: [],
        snapshot: active_snapshot,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors.first).to match(/does not match captured snapshot text version/i)
    end

    it "fast-fails deterministically when claim text does not occur in prose" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => "Completely fabricated claim that is nowhere in the summary markdown.",
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors.first).to match(/does not appear in prose/i)
    end

    it "fast-fails deterministically when declared news_usage is 'none' but prose contains visible news citations" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      result = described_class.call(
        bill: bill,
        content: summary_prose, # contains news link to baltimoresun.com
        source_uses: [],
        news_usage: "none"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors.first).to match(/declared no-news.*visible news citation/i)
    end

    it "passes immediately without calling LLM when declared news_usage is 'none' with zero news citations" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      prose_without_news = "This bill alters zoning regulations in District 4. See [Official Portal](https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345)."

      result = described_class.call(
        bill: bill,
        content: prose_without_news,
        source_uses: [],
        news_usage: "none"
      )

      expect(result).to be_valid
      expect(result).to be_supported
      expect(result.status).to eq("none")
      expect(result.errors).to be_empty
    end

    it "fast-fails deterministically with unsupported verdict when news_usage is undeclared (nil) with empty source uses" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      result = described_class.call(
        bill: bill,
        content: "Summary prose without citations.",
        source_uses: [],
        news_usage: nil
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.errors.first).to match(/missing or invalid news_usage declaration: nil/i)
    end

    it "fast-fails deterministically with unsupported verdict when news_usage is invalid" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      result = described_class.call(
        bill: bill,
        content: "Summary prose without citations.",
        source_uses: [],
        news_usage: "unrecognized_mode"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.errors.first).to match(/missing or invalid news_usage declaration: "unrecognized_mode"/i)
    end

    it "fast-fails deterministically when declared news_usage is 'cited' but source-use manifest is empty" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      result = described_class.call(
        bill: bill,
        content: "Summary prose without citations.",
        source_uses: [],
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.errors.first).to match(/declared cited news usage but source-use manifest is empty/i)
    end

    it "fast-fails deterministically when declared news_usage is 'none' but source-use manifest is not empty" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: "Summary prose without citations.",
        source_uses: source_uses,
        news_usage: "none"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.errors.first).to match(/declared no-news usage but source-use manifest is not empty/i)
    end

    it "fast-fails with unsupported verdict when snapshot belongs to a different bill" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      other_bill_snapshot = NewsArticleSourceSnapshotService.capture!(
        bill: other_bill,
        purpose: "summary",
        run_receipt: "test_receipt_other",
        sources: []
      )

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        snapshot: other_bill_snapshot,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.phase).to eq(:deterministic)
      expect(result.errors.first).to eq("Referenced snapshot does not belong to bill #{bill.id}")
    end

    it "fast-fails with unsupported verdict when cited article is not present in the referenced snapshot" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      empty_snapshot = NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: "test_receipt_empty",
        sources: []
      )

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        snapshot: empty_snapshot,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.phase).to eq(:deterministic)
      expect(result.errors.first).to eq("Bill news article #{bill_news_article.id} is not present in referenced snapshot")
    end

    it "fast-fails with unsupported verdict when snapshot captures article A but source use cites uncaptured article B" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      other_article = create(:news_article, canonical_url: "https://thebanner.com/news/other")
      other_tv = create(:news_article_text_version, :extracted, news_article: other_article, text: "Some other text.")
      other_bna = create(:bill_news_article, :approved, bill: bill, news_article: other_article, current_text_version: other_tv)

      active_snapshot = snapshot

      source_uses = [
        {
          "bill_news_article_id" => other_bna.id,
          "text_version_id" => other_tv.id,
          "claim_text" => "Some other text.",
          "evidence_excerpt" => "Some other text.",
          "citation_url" => other_article.canonical_url
        }
      ]

      prose = "According to [The Banner](https://thebanner.com/news/other), Some other text."

      result = described_class.call(
        bill: bill,
        content: prose,
        source_uses: source_uses,
        snapshot: active_snapshot,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.errors.first).to eq("Bill news article #{other_bna.id} is not present in referenced snapshot")
    end

    it "fast-fails deterministically when manifest claim has no visible citation in prose" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      prose_without_citation = "The City Council voted unanimously 14-0 to approve the zoning density bill. Official details at [Legistar](https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345)."

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: prose_without_citation,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first&.phase).to eq(:deterministic).or(be_nil)
      expect(result.errors.first).to match(/visible news citation|does not appear in prose|manifest citation/i)
    end

    it "fast-fails deterministically when manifest contains citation URL absent from visible prose in a multi-claim request" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      other_article = create(:news_article, canonical_url: "https://thebanner.com/news/other")
      other_tv = create(:news_article_text_version, :extracted, news_article: other_article, text: "Banner text context.")
      other_bna = create(:bill_news_article, :approved, bill: bill, news_article: other_article, current_text_version: other_tv)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        },
        {
          "bill_news_article_id" => other_bna.id,
          "text_version_id" => other_tv.id,
          "claim_text" => "Banner text context.",
          "evidence_excerpt" => "Banner text context.",
          "citation_url" => other_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: "#{summary_prose} Banner text context.",
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.errors.first).to match(/manifest citation.*not appear in visible prose|missing visible news citation/i)
    end

    it "fast-fails deterministically when citation URL does not belong to the referenced news article" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      unrelated_url = "https://example.org/unapproved-story"
      prose_with_unrelated = "According to [Reporting](#{unrelated_url}), #{supported_claim} Official details at [Legistar](https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345)."

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => unrelated_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: prose_with_unrelated,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.phase).to eq(:deterministic)
      expect(result.errors.first).to match(/does not belong to.*article|canonical url mismatch/i)
    end

    it "fast-fails deterministically when source use points to a text version outside the snapshot captured entry" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      active_snapshot = snapshot

      other_tv = create(
        :news_article_text_version,
        :extracted,
        news_article: news_article,
        text: "Updated text: #{article_text}"
      )
      bill_news_article.update_columns(current_text_version_id: other_tv.id, updated_at: Time.current)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => other_tv.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        snapshot: active_snapshot,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.phase).to eq(:deterministic)
      expect(result.errors.first).to match(/text version.*match.*snapshot/i)
    end

    it "fast-fails deterministically when bill news article has no selected current text version" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      bill_news_article.update_columns(current_text_version_id: nil, updated_at: Time.current)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.phase).to eq(:deterministic)
      expect(result.errors.first).to match(/no selected current text version|unselected/i)
    end

    it "fast-fails deterministically when text version is paywalled or unusable" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      paywalled_tv = create(
        :news_article_text_version,
        :paywalled,
        news_article: news_article,
        text: "Subscribe to read. #{article_text}"
      )
      bill_news_article.update_columns(current_text_version_id: paywalled_tv.id, updated_at: Time.current)

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => paywalled_tv.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.phase).to eq(:deterministic)
      expect(result.errors.first).to match(/not usable text|unusable/i)
    end

    it "prevents any LLM assessor calls when one claim fails deterministically in a mixed batch" do
      expect(mock_adapter).not_to receive(:generate_news_claim_grounding)

      other_article = create(:news_article, canonical_url: "https://thebanner.com/news/other")
      other_tv = create(:news_article_text_version, :extracted, news_article: other_article, text: "The Baltimore Banner reported other news.")
      other_bna = create(:bill_news_article, :approved, bill: bill, news_article: other_article, current_text_version: other_tv)

      multi_prose = "#{summary_prose} And according to [The Banner](https://thebanner.com/news/other), The Baltimore Banner reported other news."

      source_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        },
        {
          "bill_news_article_id" => other_bna.id,
          "text_version_id" => other_tv.id,
          "claim_text" => "The Baltimore Banner reported other news.",
          "evidence_excerpt" => "The Baltimore Banner reported other news.",
          "citation_url" => other_article.canonical_url
        }
      ]

      bill_news_article.update_columns(approved: false, updated_at: Time.current)

      result = described_class.call(
        bill: bill,
        content: multi_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
    end
  end

  describe "Phase 2: Semantic evaluation" do
    let(:source_uses) do
      [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]
    end

    it "returns supported when claim is logically entailed by the excerpt and source context" do
      expect(mock_adapter).to receive(:generate_news_claim_grounding) do |args|
        expect(args[:model]).to eq("claude-3-5-haiku-latest")
        expect(args[:prompt]).to be_a(Llm::PromptPayload)
        expect(args[:schema]).to eq(NEWS_CLAIM_GROUNDING_SCHEMA_HASH)
        {
          "verdict" => "supported",
          "reason" => "The source text directly reports that the council voted 14-0 unanimously to approve the zoning density bill."
        }
      end

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).to be_valid
      expect(result).to be_supported
      expect(result.verdict).to eq("supported")
      expect(result.claim_assessments.first.verdict).to eq("supported")
      expect(result.claim_assessments.first.phase).to eq(:semantic)
      expect(result.prompt_version).to eq(2)
      expect(result.route).to eq("claude/claude-3-5-haiku-latest")
    end

    it "returns unsupported when claim directly contradicts the source reporting" do
      contradictory_claim = "The City Council rejected the zoning density bill by a wide margin."
      contradictory_prose = "According to [The Baltimore Sun](https://baltimoresun.com/news/council-bill-density), The City Council rejected the zoning density bill by a wide margin."

      contradictory_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => contradictory_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      expect(mock_adapter).to receive(:generate_news_claim_grounding) do
        {
          "verdict" => "unsupported",
          "reason" => "The source states the council approved the bill 14-0, contradicting the claim that it was rejected."
        }
      end

      result = described_class.call(
        bill: bill,
        content: contradictory_prose,
        source_uses: contradictory_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.verdict).to eq("unsupported")
      expect(result.errors.first).to match(/contradicting the claim/i)
    end

    it "returns unsupported when claim invents a quantity or number" do
      invented_number_claim = "The zoning density bill will fund 50,000 affordable housing units."
      invented_prose = "According to [The Baltimore Sun](https://baltimoresun.com/news/council-bill-density), The zoning density bill will fund 50,000 affordable housing units."

      number_excerpt = "Sponsor Councilman Mark Conway noted that the measure will create 500 affordable units across District 4."
      invented_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => invented_number_claim,
          "evidence_excerpt" => number_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      expect(mock_adapter).to receive(:generate_news_claim_grounding) do
        {
          "verdict" => "unsupported",
          "reason" => "The article specifies 500 units, not 50,000 units."
        }
      end

      result = described_class.call(
        bill: bill,
        content: invented_prose,
        source_uses: invented_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.verdict).to eq("unsupported")
      expect(result.errors.first).to match(/500 units/i)
    end

    it "returns unsupported when claim swaps speaker or sponsor attribution" do
      attribution_swap_claim = "Opponents praised the measure for creating 500 affordable units."
      swap_prose = "According to [The Baltimore Sun](https://baltimoresun.com/news/council-bill-density), Opponents praised the measure for creating 500 affordable units."

      number_excerpt = "Sponsor Councilman Mark Conway noted that the measure will create 500 affordable units across District 4."
      swap_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => attribution_swap_claim,
          "evidence_excerpt" => number_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]

      expect(mock_adapter).to receive(:generate_news_claim_grounding) do
        {
          "verdict" => "unsupported",
          "reason" => "The statement was made by bill sponsor Conway, not opponents."
        }
      end

      result = described_class.call(
        bill: bill,
        content: swap_prose,
        source_uses: swap_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_unsupported
      expect(result.verdict).to eq("unsupported")
      expect(result.claim_assessments.first.verdict).to eq("unsupported")
      expect(result.errors.first).to match(/sponsor Conway/i)
    end

    it "returns indeterminate (fail-closed) on transport errors or timeouts" do
      expect(mock_adapter).to receive(:generate_news_claim_grounding).and_raise(
        Llm::TransportError.new("Anthropic API connection timed out after 30 seconds")
      )

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_indeterminate
      expect(result.verdict).to eq("indeterminate")
      expect(result.claim_assessments.first.verdict).to eq("indeterminate")
      expect(result.errors.first).to match(/timed out/i)
    end

    it "returns indeterminate (fail-closed) on schema validation errors" do
      expect(mock_adapter).to receive(:generate_news_claim_grounding).and_raise(
        Llm::SchemaError.new("Model output missing required property 'verdict'")
      )

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited"
      )

      expect(result).not_to be_valid
      expect(result).to be_indeterminate
      expect(result.verdict).to eq("indeterminate")
      expect(result.claim_assessments.first.verdict).to eq("indeterminate")
      expect(result.errors.first).to match(/missing required property/i)
    end

    it "persists evaluated verdicts to NewsArticleSourceUse records via update_columns when persist: true" do
      persisted_source_use = snapshot.source_uses.create!(
        bill_news_article: bill_news_article,
        text_version: text_version,
        claim_text: supported_claim,
        evidence_excerpt: verbatim_excerpt,
        citation_url: news_article.canonical_url,
        grounding_status: "pending"
      )

      expect(mock_adapter).to receive(:generate_news_claim_grounding).and_return({
        "verdict" => "supported",
        "reason" => "Entailed by text."
      })

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: [persisted_source_use],
        persist: true
      )

      expect(result).to be_valid
      expect(result).to be_supported

      persisted_source_use.reload
      expect(persisted_source_use.grounding_status).to eq("supported")
      expect(persisted_source_use.grounding_reason).to eq("Entailed by text.")
    end

    context "when candidate summary contains reference definitions" do
      it "rejects when citation URL appears only in an unused reference definition" do
        unused_prose = "#{supported_claim}\n\n[source]: #{news_article.canonical_url}"

        result = described_class.call(
          bill: bill,
          content: unused_prose,
          source_uses: source_uses,
          news_usage: "cited"
        )

        expect(result).not_to be_valid
        expect(result).to be_unsupported
        expect(result.claim_assessments.first.verdict).to eq("unsupported")
        expect(result.claim_assessments.first.reason).to match(/does not appear in visible prose/)
      end

      it "accepts when citation URL appears in a used reference-style link" do
        used_prose = "#{supported_claim} [Source][source]\n\n[source]: #{news_article.canonical_url}"

        expect(mock_adapter).to receive(:generate_news_claim_grounding).and_return({
          "verdict" => "supported",
          "reason" => "Entailed by text."
        })

        result = described_class.call(
          bill: bill,
          content: used_prose,
          source_uses: source_uses,
          news_usage: "cited"
        )

        expect(result).to be_valid
        expect(result).to be_supported
        expect(result.claim_assessments.first.verdict).to eq("supported")
      end
    end

    context "when candidate summary contains multiple claims or omitted claims sharing a news URL" do
      it "refuses when an unmanifested contradictory claim cites the same news URL" do
        multi_prose = "#{supported_claim} [Source](#{news_article.canonical_url})\n\n" \
          "The same report says the council approved 999 new parks. [Source](#{news_article.canonical_url})"

        allow(mock_adapter).to receive(:generate_news_claim_grounding) do |args|
          if args[:prompt].user_message.include?("999")
            {
              "verdict" => "unsupported",
              "reason" => "The source approves 500 affordable units and 14-0 vote, not 999 new parks."
            }
          else
            {
              "verdict" => "supported",
              "reason" => "Entailed by source text."
            }
          end
        end

        result = described_class.call(
          bill: bill,
          content: multi_prose,
          source_uses: source_uses,
          news_usage: "cited"
        )

        expect(result).not_to be_valid
        expect(result).to be_unsupported
        expect(result.verdict).to eq("unsupported")
        expect(result.claim_assessments.any?(&:unsupported?)).to be true
        expect(result.errors.first).to match(/999/i)
      end

      it "accepts when candidate prose contains multiple distinct supported claims from one URL" do
        second_claim = "Sponsor Mark Conway noted the measure will create 500 affordable units."
        multi_prose = "#{supported_claim} [Source](#{news_article.canonical_url})\n\n" \
          "#{second_claim} [Source](#{news_article.canonical_url})"

        multi_uses = [
          {
            "bill_news_article_id" => bill_news_article.id,
            "text_version_id" => text_version.id,
            "claim_text" => supported_claim,
            "evidence_excerpt" => verbatim_excerpt,
            "citation_url" => news_article.canonical_url
          },
          {
            "bill_news_article_id" => bill_news_article.id,
            "text_version_id" => text_version.id,
            "claim_text" => second_claim,
            "evidence_excerpt" => "Sponsor Councilman Mark Conway noted that the measure will create 500 affordable units across District 4.",
            "citation_url" => news_article.canonical_url
          }
        ]

        allow(mock_adapter).to receive(:generate_news_claim_grounding).and_return({
          "verdict" => "supported",
          "reason" => "Directly supported by the text."
        })

        result = described_class.call(
          bill: bill,
          content: multi_prose,
          source_uses: multi_uses,
          news_usage: "cited"
        )

        expect(result).to be_valid
        expect(result).to be_supported
        expect(result.verdict).to eq("supported")
        expect(result.claim_assessments.all?(&:supported?)).to be true
      end

      it "accepts mixed official bill text plus cited reporting without evaluating official statements as news claims" do
        official_url = "https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345"
        mixed_prose = "The official record is maintained at [Legistar](#{official_url}). " \
          "According to [The Baltimore Sun](#{news_article.canonical_url}), #{supported_claim}"

        expect(mock_adapter).to receive(:generate_news_claim_grounding) do |args|
          expect(args[:prompt].user_message).not_to include(official_url)
          {
            "verdict" => "supported",
            "reason" => "Council approved the bill is supported."
          }
        end

        result = described_class.call(
          bill: bill,
          content: mixed_prose,
          source_uses: source_uses,
          news_usage: "cited"
        )

        expect(result).to be_valid
        expect(result).to be_supported
      end

      it "refuses when an omitted contradictory claim cites an approved article via reference-style link" do
        ref_prose = "#{supported_claim} [Source][news_ref]\n\n" \
          "The same report says the council approved 999 new parks. [Source][news_ref]\n\n" \
          "[news_ref]: #{news_article.canonical_url}"

        allow(mock_adapter).to receive(:generate_news_claim_grounding) do |args|
          if args[:prompt].user_message.include?("999")
            {
              "verdict" => "unsupported",
              "reason" => "Contradicts source text."
            }
          else
            {
              "verdict" => "supported",
              "reason" => "Entailed by source text."
            }
          end
        end

        result = described_class.call(
          bill: bill,
          content: ref_prose,
          source_uses: source_uses,
          news_usage: "cited"
        )

        expect(result).not_to be_valid
        expect(result).to be_unsupported
        expect(result.claim_assessments.any?(&:unsupported?)).to be true
      end
    end
  end

  describe "reasoning_effort forwarding to adapter" do
    let(:source_uses) do
      [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        }
      ]
    end

    let(:openrouter_adapter) do
      instance_double(Llm::OpenRouterAdapter, provider_label: "openrouter")
    end

    let(:claude_adapter) do
      instance_double(Llm::ClaudeAdapter, provider_label: "claude")
    end

    it "forwards reasoning_effort to openrouter adapter when route has reasoning_effort present" do
      openrouter_route = Llm::RouteResolver::Route.new(
        provider: :openrouter,
        api_model: "openai/o3-mini",
        reasoning_effort: "high"
      )

      expect(openrouter_adapter).to receive(:generate_news_claim_grounding).with(
        prompt: anything,
        model: "openai/o3-mini",
        schema: NEWS_CLAIM_GROUNDING_SCHEMA_HASH,
        reasoning_effort: "high"
      ).and_return({
        "verdict" => "supported",
        "reason" => "The source text directly reports that the council voted 14-0 unanimously to approve the zoning density bill."
      })

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited",
        route: openrouter_route,
        adapter: openrouter_adapter,
        model: "openai/o3-mini"
      )

      expect(result).to be_valid
      expect(result).to be_supported
    end

    it "omits reasoning_effort when route has nil reasoning_effort for openrouter adapter" do
      openrouter_route = Llm::RouteResolver::Route.new(
        provider: :openrouter,
        api_model: "meta-llama/llama-3.3-70b-instruct",
        reasoning_effort: nil
      )

      expect(openrouter_adapter).to receive(:generate_news_claim_grounding).with(
        prompt: anything,
        model: "meta-llama/llama-3.3-70b-instruct",
        schema: NEWS_CLAIM_GROUNDING_SCHEMA_HASH
      ).and_return({
        "verdict" => "supported",
        "reason" => "The source text directly reports that the council voted 14-0 unanimously to approve the zoning density bill."
      })

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited",
        route: openrouter_route,
        adapter: openrouter_adapter,
        model: "meta-llama/llama-3.3-70b-instruct"
      )

      expect(result).to be_valid
      expect(result).to be_supported
    end

    it "omits reasoning_effort when adapter provider_label is not openrouter even if route has reasoning_effort" do
      claude_route = Llm::RouteResolver::Route.new(
        provider: :claude,
        api_model: "claude-3-5-haiku-latest",
        reasoning_effort: "high"
      )

      expect(claude_adapter).to receive(:generate_news_claim_grounding).with(
        prompt: anything,
        model: "claude-3-5-haiku-latest",
        schema: NEWS_CLAIM_GROUNDING_SCHEMA_HASH
      ).and_return({
        "verdict" => "supported",
        "reason" => "The source text directly reports that the council voted 14-0 unanimously to approve the zoning density bill."
      })

      result = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: source_uses,
        news_usage: "cited",
        route: claude_route,
        adapter: claude_adapter,
        model: "claude-3-5-haiku-latest"
      )

      expect(result).to be_valid
      expect(result).to be_supported
    end
  end

  describe "multi-claim aggregation, unrecognized verdicts, URL subterfuge, and immutability" do
    it "aggregates supported + indeterminate to indeterminate, unsupported + indeterminate to unsupported, and treats unrecognized LLM verdict strings as indeterminate" do
      article_2 = create(
        :news_article,
        canonical_url: "https://thebanner.com/news/transit-plan",
        outlet_name: "The Baltimore Banner",
        title: "Council Reviews Transit Plan"
      )
      tv_2 = create(
        :news_article_text_version,
        :extracted,
        news_article: article_2,
        text: "The Baltimore City Council reviewed a transit plan allocating 10 million dollars for bus lanes."
      )
      bna_2 = create(:bill_news_article, :approved, bill: bill, news_article: article_2, current_text_version: tv_2)

      multi_snap = NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: "multi_agg_snap",
        sources: [bill_news_article, bna_2]
      )

      dual_uses = [
        {
          "bill_news_article_id" => bill_news_article.id,
          "text_version_id" => text_version.id,
          "claim_text" => supported_claim,
          "evidence_excerpt" => verbatim_excerpt,
          "citation_url" => news_article.canonical_url
        },
        {
          "bill_news_article_id" => bna_2.id,
          "text_version_id" => tv_2.id,
          "claim_text" => "Council allocated 10 million dollars for bus lanes.",
          "evidence_excerpt" => "allocating 10 million dollars for bus lanes",
          "citation_url" => article_2.canonical_url
        }
      ]
      dual_prose = "According to [The Banner](#{news_article.canonical_url}), #{supported_claim} " \
        "Additionally, [The Banner](#{article_2.canonical_url}) noted Council allocated 10 million dollars for bus lanes."

      call_idx = 0
      allow(mock_adapter).to receive(:generate_news_claim_grounding) do
        call_idx += 1
        if call_idx == 1
          {"verdict" => "supported", "reason" => "Supported by first article."}
        else
          {"verdict" => "partially_supported", "reason" => "Unrecognized verdict string."}
        end
      end

      res_indet = described_class.call(
        bill: bill,
        content: dual_prose,
        source_uses: dual_uses,
        snapshot: multi_snap,
        news_usage: "cited",
        adapter: mock_adapter,
        route: mock_route
      )
      expect(res_indet).to be_indeterminate
      expect(res_indet.verdict).to eq("indeterminate")
      expect(res_indet.claim_assessments.last.verdict).to eq("indeterminate")

      call_idx = 0
      allow(mock_adapter).to receive(:generate_news_claim_grounding) do
        call_idx += 1
        if call_idx == 1
          {"verdict" => "indeterminate", "reason" => "Ambiguous phrasing."}
        else
          {"verdict" => "unsupported", "reason" => "Contradicted by second article."}
        end
      end

      res_unsup = described_class.call(
        bill: bill,
        content: dual_prose,
        source_uses: dual_uses,
        snapshot: multi_snap,
        news_usage: "cited",
        adapter: mock_adapter,
        route: mock_route
      )
      expect(res_unsup).to be_unsupported
      expect(res_unsup.verdict).to eq("unsupported")
    end

    it "enforces ReadOnlyRecord after creation on NewsArticleSourceUse, NewsArticleSourceSnapshot, and NewsArticleTextVersion, while allowing grounding status persistence" do
      allow(mock_adapter).to receive(:generate_news_claim_grounding).and_return({
        "verdict" => "supported",
        "reason" => "Supported by source text."
      })

      source_use = snapshot.source_uses.create!(
        bill_news_article: bill_news_article,
        text_version: text_version,
        claim_text: supported_claim,
        evidence_excerpt: verbatim_excerpt,
        citation_url: news_article.canonical_url,
        grounding_status: "pending"
      )

      expect { source_use.update!(claim_text: "Mutated") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { source_use.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { snapshot.update!(purpose: "testimony") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { text_version.update!(text: "Mutated") }.to raise_error(ActiveRecord::ReadOnlyRecord)

      res = described_class.call(
        bill: bill,
        content: summary_prose,
        source_uses: [source_use.reload],
        snapshot: snapshot,
        news_usage: "cited",
        adapter: mock_adapter,
        route: mock_route,
        persist: true
      )
      expect(res).to be_supported
      expect(source_use.reload.grounding_status).to eq("supported")
    end

    it "supports string and symbol text_version_id and news_article_text_version_id keys in NewsArticleSourceSnapshot#source_entries" do
      snap_sym = NewsArticleSourceSnapshot.create!(
        bill: bill,
        purpose: "summary",
        run_receipt: "sym_keys_snap",
        source_entries: [
          {
            bill_news_article_id: bill_news_article.id,
            news_article_text_version_id: text_version.id,
            canonical_url: news_article.canonical_url,
            text_digest: text_version.digest,
            review_version: bill_news_article.review_version,
            stance_version: bill_news_article.stance_version
          }
        ]
      )
      expect(snap_sym.captured_text_version_ids).to eq([text_version.id])
    end

    it "rejects omitted prose claims citing URL subterfuge variants (capitalized host, fragment, query params, trailing slash)" do
      [
        "https://THEBANNER.COM/politics/2026/03/20/zoning-density-vote/",
        "#{news_article.canonical_url}#section-2",
        "#{news_article.canonical_url}?utm_source=newsletter",
        "#{news_article.canonical_url}/"
      ].each do |variant_url|
        prose_with_subterfuge = "#{summary_prose}\n\nAnother unverified claim citing [The Banner](#{variant_url})."
        res = described_class.call(
          bill: bill,
          content: prose_with_subterfuge,
          source_uses: [
            {
              "bill_news_article_id" => bill_news_article.id,
              "text_version_id" => text_version.id,
              "claim_text" => supported_claim,
              "evidence_excerpt" => verbatim_excerpt,
              "citation_url" => news_article.canonical_url
            }
          ],
          snapshot: snapshot,
          news_usage: "cited",
          adapter: mock_adapter,
          route: mock_route
        )
        expect(res).to be_unsupported
      end
    end
  end
end
