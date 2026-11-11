# frozen_string_literal: true

require "rails_helper"

# @lat: [[news-article-evidence#Source snapshots and claim uses]]
# @lat: [[news-gate#Why ungrounded generations are quarantined as draft revisions]]
RSpec.describe NewsSummaryManifestValidator, type: :service do
  let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
  let(:bill) do
    create(
      :bill,
      external_id: "MANIFEST-VALIDATOR-SPEC",
      sway_locale: sway_locale,
      extracted_text: "Section 1. City Council authorizes municipal infrastructure improvements.",
      link: "https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345"
    )
  end

  let(:news_article) do
    create(
      :news_article,
      canonical_url: "https://example.com/baltimore-transit",
      outlet_name: "The Baltimore Sun",
      title: "City Council Approves Transit Expansion"
    )
  end

  let(:text_version) do
    create(
      :news_article_text_version,
      :extracted,
      news_article: news_article,
      text: "The council approved 50 new transit hubs across the metropolitan district on Wednesday."
    )
  end

  let!(:bna) do
    create(
      :bill_news_article,
      :approved,
      bill: bill,
      news_article: news_article,
      current_text_version: text_version,
      match_kind: "direct"
    )
  end

  let(:snapshot) do
    NewsArticleSourceSnapshotService.capture!(
      bill: bill,
      purpose: "summary",
      run_receipt: "validator_spec_receipt",
      sources: [bna]
    )
  end

  describe "declaration validation" do
    it "fails when news_usage is nil" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose",
        news_usage: nil,
        source_uses: [],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:invalid_news_usage)
      expect(res.errors.first).to include("Missing or invalid news_usage declaration")
      expect(res.structured_refusal).to be_present
      expect(res.structured_refusal&.supported?).to be false
    end

    it "fails when news_usage is blank" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose",
        news_usage: "   ",
        source_uses: [],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:invalid_news_usage)
    end

    it "fails when news_usage is unrecognized string" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose",
        news_usage: "speculative",
        source_uses: [],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:invalid_news_usage)
    end
  end

  describe "news_usage == 'none' boundary checks" do
    it "fails when source_uses contains entries" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Clean prose without URLs",
        news_usage: "none",
        source_uses: [{"foo" => "bar"}],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:non_empty_manifest)
      expect(res.errors).to include("Declared no-news usage but source-use manifest is not empty")
    end

    it "fails when prose contains visible news citations" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Clean prose citing [The Sun](https://example.com/baltimore-transit)",
        news_usage: "none",
        source_uses: [],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:undeclared_news_links)
      expect(res.errors.first).to include("Declared no-news usage but content contains visible news citations")
    end

    it "passes when prose contains official bill URL and source_uses is empty" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose referencing [Legistar](https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=12345)",
        news_usage: "none",
        source_uses: [],
        snapshot: snapshot
      )
      expect(res.valid?).to be true
      expect(res.errors).to be_empty
      expect(res.structured_refusal).to be_nil
    end
  end

  describe "news_usage == 'cited' boundary checks" do
    it "fails when snapshot is nil" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose [Sun](https://example.com/baltimore-transit)",
        news_usage: "cited",
        source_uses: [
          {
            "bill_news_article_id" => bna.id,
            "text_version_id" => text_version.id,
            "claim_text" => "50 new transit hubs",
            "evidence_excerpt" => "approved 50 new transit hubs",
            "citation_url" => "https://example.com/baltimore-transit"
          }
        ],
        snapshot: nil
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:missing_snapshot)
    end

    it "fails when snapshot belongs to another bill" do
      other_bill = create(:bill, sway_locale: sway_locale)
      other_snapshot = NewsArticleSourceSnapshotService.capture!(
        bill: other_bill,
        purpose: "summary",
        run_receipt: "other_bill_receipt",
        sources: []
      )

      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose [Sun](https://example.com/baltimore-transit)",
        news_usage: "cited",
        source_uses: [
          {
            "bill_news_article_id" => bna.id,
            "text_version_id" => text_version.id,
            "claim_text" => "50 new transit hubs",
            "evidence_excerpt" => "approved 50 new transit hubs",
            "citation_url" => "https://example.com/baltimore-transit"
          }
        ],
        snapshot: other_snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:cross_bill_snapshot)
    end

    it "fails when source_uses array is empty and prose has no news citations" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose without any news citations.",
        news_usage: "cited",
        source_uses: [],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:empty_manifest)
    end

    it "validates when source_uses array is empty and prose links to an approved article in snapshot" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose [Sun](https://example.com/baltimore-transit)",
        news_usage: "cited",
        source_uses: [],
        snapshot: snapshot
      )
      expect(res.valid?).to be true
      expect(res.news_usage).to eq("cited")
    end

    it "fails when source_uses array is empty and prose links to an unapproved url" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose [Unknown](https://example.com/unapproved-story)",
        news_usage: "cited",
        source_uses: [],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:canonical_url_mismatch)
    end

    it "fails when source_uses array is empty and article approval is withdrawn or snapshot text_version_id is nil or mismatched" do
      active_snapshot = snapshot
      bna.update_columns(approved: false)

      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose [Sun](https://example.com/baltimore-transit)",
        news_usage: "cited",
        source_uses: [],
        snapshot: active_snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:unapproved_article)

      bna.update_columns(approved: true)
      allow(active_snapshot).to receive(:captured_source_entries).and_return(
        [{"bill_news_article_id" => bna.id, "text_version_id" => nil, "approved" => true}]
      )

      nil_tv_res = described_class.call(
        bill: bill,
        summary_markdown: "Prose [Sun](https://example.com/baltimore-transit)",
        news_usage: "cited",
        source_uses: [],
        snapshot: active_snapshot
      )
      expect(nil_tv_res.valid?).to be false
      expect(nil_tv_res.reasons).to include(:snapshot_text_version_mismatch)
    end

    it "fails when claim_text is not found in prose" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose with citation [The Sun](https://example.com/baltimore-transit) but completely different wording.",
        news_usage: "cited",
        source_uses: [
          {
            "bill_news_article_id" => bna.id,
            "text_version_id" => text_version.id,
            "claim_text" => "50 new transit hubs",
            "evidence_excerpt" => "approved 50 new transit hubs",
            "citation_url" => "https://example.com/baltimore-transit"
          }
        ],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:claim_text_missing_from_prose)
    end

    it "fails when citation_url does not appear in prose" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose mentioning 50 new transit hubs without the link.",
        news_usage: "cited",
        source_uses: [
          {
            "bill_news_article_id" => bna.id,
            "text_version_id" => text_version.id,
            "claim_text" => "50 new transit hubs",
            "evidence_excerpt" => "approved 50 new transit hubs",
            "citation_url" => "https://example.com/baltimore-transit"
          }
        ],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:manifest_url_not_in_prose)
    end

    it "fails when text version extraction_status is not usable" do
      unusable_tv = create(
        :news_article_text_version,
        :paywalled,
        news_article: news_article
      )
      bna.update_columns(current_text_version_id: unusable_tv.id)
      snap = NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: "unusable_snap",
        sources: [bna]
      )

      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose mentioning 50 new transit hubs [The Sun](https://example.com/baltimore-transit).",
        news_usage: "cited",
        source_uses: [
          {
            "bill_news_article_id" => bna.id,
            "text_version_id" => unusable_tv.id,
            "claim_text" => "50 new transit hubs",
            "evidence_excerpt" => "approved 50 new transit hubs",
            "citation_url" => "https://example.com/baltimore-transit"
          }
        ],
        snapshot: snap
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:unusable_text)
    end

    it "fails when citation_url does not match canonical_url of article" do
      res = described_class.call(
        bill: bill,
        summary_markdown: "Prose mentioning 50 new transit hubs [The Sun](https://example.com/spoofed-transit).",
        news_usage: "cited",
        source_uses: [
          {
            "bill_news_article_id" => bna.id,
            "text_version_id" => text_version.id,
            "claim_text" => "50 new transit hubs",
            "evidence_excerpt" => "approved 50 new transit hubs",
            "citation_url" => "https://example.com/spoofed-transit"
          }
        ],
        snapshot: snapshot
      )
      expect(res.valid?).to be false
      expect(res.reasons).to include(:canonical_url_mismatch)
    end
  end
end
