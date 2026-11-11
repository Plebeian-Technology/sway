# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: news_article_source_uses
# Database name: primary
#
#  id                              :integer          not null, primary key
#  citation_url                    :string           not null
#  claim_text                      :text             not null
#  evidence_excerpt                :text             not null
#  grounding_reason                :text
#  grounding_status                :string           default("pending"), not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  bill_news_article_id            :integer          not null
#  news_article_source_snapshot_id :integer          not null
#  text_version_id                 :integer          not null
#
# Indexes
#
#  idx_on_news_article_source_snapshot_id_400dbd1ea3       (news_article_source_snapshot_id)
#  index_news_article_source_uses_on_bill_news_article_id  (bill_news_article_id)
#  index_news_article_source_uses_on_text_version_id       (text_version_id)
#  index_source_uses_on_bill_news_article_id               (bill_news_article_id)
#  index_source_uses_on_snapshot_and_status                (news_article_source_snapshot_id,grounding_status)
#  index_source_uses_on_snapshot_id                        (news_article_source_snapshot_id)
#  index_source_uses_on_text_version_id                    (text_version_id)
#
# Foreign Keys
#
#  bill_news_article_id             (bill_news_article_id => bill_news_articles.id) ON DELETE => restrict
#  news_article_source_snapshot_id  (news_article_source_snapshot_id => news_article_source_snapshots.id) ON DELETE => cascade
#  text_version_id                  (text_version_id => news_article_text_versions.id) ON DELETE => restrict
#
RSpec.describe NewsArticleSourceUse, type: :model do
  # @lat: [[news-article-evidence#Source snapshots and claim uses]]
  let(:bill) { create(:bill) }
  let(:news_article) { create(:news_article) }
  let(:text_version) { create(:news_article_text_version, :extracted, news_article:, text: "The Baltimore City Council voted unanimously 14-0 on the bill.") }
  let(:bill_news_article) { create(:bill_news_article, :approved, bill:, news_article:, current_text_version: text_version) }
  let(:snapshot) { create(:news_article_source_snapshot, bill:) }

  describe "validations" do
    it "is valid with matching bill, article, and verbatim excerpt" do
      use = build(
        :news_article_source_use,
        news_article_source_snapshot: snapshot,
        bill_news_article:,
        text_version:,
        claim_text: "Council approved the measure 14-0.",
        evidence_excerpt: "voted unanimously 14-0",
        citation_url: news_article.canonical_url
      )
      expect(use).to be_valid
    end

    it "rejects when evidence_excerpt does not appear verbatim in text_version.text" do
      use = build(
        :news_article_source_use,
        news_article_source_snapshot: snapshot,
        bill_news_article:,
        text_version:,
        claim_text: "Council approved the measure 14-0.",
        evidence_excerpt: "voted overwhelmingly by 12 votes",
        citation_url: news_article.canonical_url
      )
      expect(use).not_to be_valid
      expect(use.errors[:evidence_excerpt]).to include("must appear verbatim in the referenced text version")
    end

    it "rejects when bill_news_article belongs to a different bill" do
      other_bill = create(:bill)
      other_bna = create(:bill_news_article, :approved, bill: other_bill, news_article:, current_text_version: text_version)

      use = build(
        :news_article_source_use,
        news_article_source_snapshot: snapshot,
        bill_news_article: other_bna,
        text_version:,
        claim_text: "Council approved the measure.",
        evidence_excerpt: "voted unanimously 14-0",
        citation_url: news_article.canonical_url
      )
      expect(use).not_to be_valid
      expect(use.errors[:bill_news_article]).to include("must belong to the snapshot's bill")
    end

    it "rejects when text_version belongs to a different news_article" do
      foreign_article = create(:news_article)
      foreign_text = create(:news_article_text_version, :extracted, news_article: foreign_article, text: "Unrelated text.")

      use = build(
        :news_article_source_use,
        news_article_source_snapshot: snapshot,
        bill_news_article:,
        text_version: foreign_text,
        claim_text: "Unrelated claim.",
        evidence_excerpt: "Unrelated text.",
        citation_url: foreign_article.canonical_url
      )
      expect(use).not_to be_valid
      expect(use.errors[:text_version]).to include("must belong to the associated bill news article")
    end

    it "enforces grounding_status enum inclusion" do
      %w[pending supported unsupported indeterminate].each do |status|
        use = build(
          :news_article_source_use,
          news_article_source_snapshot: snapshot,
          bill_news_article:,
          text_version:,
          evidence_excerpt: "voted unanimously 14-0",
          grounding_status: status
        )
        expect(use).to be_valid
      end

      use_bad = build(
        :news_article_source_use,
        news_article_source_snapshot: snapshot,
        bill_news_article:,
        text_version:,
        evidence_excerpt: "voted unanimously 14-0",
        grounding_status: "verified_true"
      )
      expect(use_bad).not_to be_valid
      expect(use_bad.errors[:grounding_status]).to be_present
    end
  end

  describe "aliases" do
    let(:use) do
      build(
        :news_article_source_use,
        news_article_source_snapshot: snapshot,
        bill_news_article:,
        text_version:,
        evidence_excerpt: "voted unanimously 14-0",
        grounding_status: "supported"
      )
    end

    it "aliases verbatim_excerpt to evidence_excerpt" do
      expect(use.verbatim_excerpt).to eq("voted unanimously 14-0")
      use.verbatim_excerpt = "new excerpt"
      expect(use.evidence_excerpt).to eq("new excerpt")
    end

    it "aliases grounding_verdict to grounding_status" do
      expect(use.grounding_verdict).to eq("supported")
      use.grounding_verdict = "unsupported"
      expect(use.grounding_status).to eq("unsupported")
    end

    it "aliases snapshot to news_article_source_snapshot" do
      expect(use.snapshot).to eq(snapshot)
    end
  end

  describe "immutability" do
    let(:use) do
      create(
        :news_article_source_use,
        news_article_source_snapshot: snapshot,
        bill_news_article:,
        text_version:,
        evidence_excerpt: "voted unanimously 14-0"
      )
    end

    it "is readonly when persisted" do
      expect(use).to be_readonly
    end

    it "raises ActiveRecord::ReadOnlyRecord on update attempt" do
      expect {
        use.update(claim_text: "Tampered claim")
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on destroy attempt" do
      expect {
        use.destroy
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
