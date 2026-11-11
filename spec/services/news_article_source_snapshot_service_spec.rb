# frozen_string_literal: true

require "rails_helper"

RSpec.describe NewsArticleSourceSnapshotService do
  # @lat: [[news-article-evidence#Source snapshots and claim uses]]
  let(:bill) { create(:bill) }
  let(:news_article) { create(:news_article) }
  let(:text_version) { create(:news_article_text_version, :extracted, news_article:, text: "Public hearing set for Thursday.") }
  let!(:bna) { create(:bill_news_article, :approved, bill:, news_article:, current_text_version: text_version) }

  describe ".capture!" do
    it "creates a snapshot and captures all approved, text-bearing associations automatically" do
      snapshot = described_class.capture!(bill:, purpose: "summary")

      expect(snapshot).to be_persisted
      expect(snapshot.bill).to eq(bill)
      expect(snapshot.purpose).to eq("summary")
      expect(snapshot.source_entries.size).to eq(1)

      entry = snapshot.source_entries.first
      expect(entry["bill_news_article_id"]).to eq(bna.id)
      expect(entry["news_article_id"]).to eq(news_article.id)
      expect(entry["text_version_id"]).to eq(text_version.id)
      expect(entry["text_digest"]).to eq(text_version.digest)
      expect(entry["review_version"]).to eq(bna.review_version)
      expect(entry["approved"]).to be true
    end

    it "creates associated NewsArticleSourceUse records when attributes are provided" do
      snapshot = described_class.capture!(
        bill:,
        purpose: "summary",
        source_uses_attributes: [
          {
            bill_news_article: bna,
            text_version: text_version,
            claim_text: "Hearing scheduled for Thursday.",
            evidence_excerpt: "hearing set for Thursday",
            citation_url: news_article.canonical_url
          }
        ]
      )

      expect(snapshot.news_article_source_uses.count).to eq(1)
      use = snapshot.news_article_source_uses.first
      expect(use.claim_text).to eq("Hearing scheduled for Thursday.")
      expect(use.evidence_excerpt).to eq("hearing set for Thursday")
      expect(use.citation_url).to eq(news_article.canonical_url)
    end

    it "rolls back snapshot creation if any source use validation fails" do
      expect {
        described_class.capture!(
          bill:,
          purpose: "summary",
          source_uses_attributes: [
            {
              bill_news_article: bna,
              text_version: text_version,
              claim_text: "Hearing scheduled for Thursday.",
              evidence_excerpt: "NON_EXISTENT_EXCERPT",
              citation_url: news_article.canonical_url
            }
          ]
        )
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(NewsArticleSourceSnapshot.count).to eq(0)
      expect(NewsArticleSourceUse.count).to eq(0)
    end
  end

  describe ".compare_eligibility" do
    it "returns eligible comparison when live state matches captured state" do
      snapshot = described_class.capture!(bill:, purpose: "summary")
      comparison = described_class.compare_eligibility(snapshot)

      expect(comparison.eligible?).to be true
      expect(comparison.mismatches).to be_empty
      expect(comparison.stale_reasons).to be_empty
    end

    it "detects when association approval is withdrawn" do
      snapshot = described_class.capture!(bill:, purpose: "summary")
      admin = create(:user, :sway_admin)
      bna.withdraw_approval!(by: admin)

      comparison = described_class.compare_eligibility(snapshot)
      expect(comparison.eligible?).to be false
      expect(comparison.stale_reasons).to include(:approval_withdrawn)
    end
  end
end
