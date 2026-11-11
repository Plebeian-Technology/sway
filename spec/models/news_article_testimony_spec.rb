# frozen_string_literal: true

require "rails_helper"

# @lat: [[news-testimony#Grounding published opinion testimony in article evidence]]
# == Schema Information
#
# Table name: news_article_testimonies
# Database name: primary
#
#  id                              :integer          not null, primary key
#  argument_markdown               :text             not null
#  author_name                     :string
#  citation_url                    :string           not null
#  evidence_excerpt                :text             not null
#  outlet_name                     :string           not null
#  publication_state               :string           default("draft"), not null
#  published_at                    :datetime
#  review_version                  :integer          default(0), not null
#  stance                          :string           not null
#  stance_version                  :integer          default(0), not null
#  text_digest                     :string           not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  bill_news_article_id            :integer          not null
#  news_article_source_snapshot_id :integer
#  news_article_text_version_id    :integer          not null
#
# Indexes
#
#  idx_news_testimonies_on_bna_and_pub_state               (bill_news_article_id,publication_state)
#  idx_news_testimonies_on_snapshot_id                     (news_article_source_snapshot_id)
#  idx_news_testimonies_on_text_version_id                 (news_article_text_version_id)
#  index_news_article_testimonies_on_bill_news_article_id  (bill_news_article_id)
#
# Foreign Keys
#
#  bill_news_article_id             (bill_news_article_id => bill_news_articles.id) ON DELETE => cascade
#  news_article_source_snapshot_id  (news_article_source_snapshot_id => news_article_source_snapshots.id) ON DELETE => nullify
#  news_article_text_version_id     (news_article_text_version_id => news_article_text_versions.id) ON DELETE => restrict
#
RSpec.describe NewsArticleTestimony, type: :model do
  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:news_article) { create(:news_article, :op_ed, outlet_name: "The Baltimore Sun", canonical_url: "https://baltimoresun.com/opinion/sample") }
  let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "Verbatim article evidence for the testimony model.") }
  let(:bna) { create(:bill_news_article, :approved, :support, bill: bill, news_article: news_article, current_text_version: text_version) }
  let(:snapshot) { create(:news_article_source_snapshot, :testimony, bill: bill, source_entries: [{"bill_news_article_id" => bna.id}]) }

  subject(:testimony) do
    build(
      :news_article_testimony,
      bill_news_article: bna,
      news_article_source_snapshot: snapshot,
      news_article_text_version: text_version,
      argument_markdown: "Argument supported by the text.",
      evidence_excerpt: "Verbatim article evidence",
      citation_url: "https://baltimoresun.com/opinion/sample",
      outlet_name: "The Baltimore Sun",
      author_name: "Columnist",
      stance: "support",
      stance_version: bna.stance_version,
      review_version: bna.review_version,
      text_digest: text_version.digest,
      publication_state: "draft"
    )
  end

  describe "validations" do
    it "is valid with valid attributes" do
      expect(testimony).to be_valid
    end

    it "requires argument_markdown" do
      testimony.argument_markdown = ""
      expect(testimony).not_to be_valid
      expect(testimony.errors[:argument_markdown]).to be_present
    end

    it "requires evidence_excerpt" do
      testimony.evidence_excerpt = ""
      expect(testimony).not_to be_valid
      expect(testimony.errors[:evidence_excerpt]).to be_present
    end

    it "requires evidence_excerpt to appear verbatim in referenced text_version" do
      testimony.evidence_excerpt = "Non-existent phrase in source text"
      expect(testimony).not_to be_valid
      expect(testimony.errors[:evidence_excerpt]).to include("must appear verbatim in the referenced text version")
    end

    it "requires outlet_name" do
      testimony.outlet_name = ""
      expect(testimony).not_to be_valid
      expect(testimony.errors[:outlet_name]).to be_present
    end

    it "requires citation_url" do
      testimony.citation_url = ""
      expect(testimony).not_to be_valid
      expect(testimony.errors[:citation_url]).to be_present
    end

    it "requires stance to be support or oppose" do
      testimony.stance = "neutral"
      expect(testimony).not_to be_valid
      expect(testimony.errors[:stance]).to be_present

      testimony.stance = "support"
      expect(testimony).to be_valid

      testimony.stance = "oppose"
      expect(testimony).to be_valid
    end

    it "requires text_digest" do
      testimony.text_digest = ""
      expect(testimony).not_to be_valid
      expect(testimony.errors[:text_digest]).to be_present
    end

    it "requires publication_state to be draft, published, or withdrawn" do
      testimony.publication_state = "invalid_state"
      expect(testimony).not_to be_valid
      expect(testimony.errors[:publication_state]).to be_present

      testimony.publication_state = "draft"
      expect(testimony).to be_valid

      testimony.publication_state = "published"
      expect(testimony).to be_valid
    end

    it "enforces non-negative integer stance_version and review_version" do
      testimony.stance_version = -1
      expect(testimony).not_to be_valid

      testimony.stance_version = 0
      testimony.review_version = -1
      expect(testimony).not_to be_valid
    end

    it "enforces cross-bill isolation between bill_news_article and snapshot" do
      other_bill = create(:bill, sway_locale: sway_locale)
      other_snapshot = create(:news_article_source_snapshot, :testimony, bill: other_bill)
      testimony.news_article_source_snapshot = other_snapshot

      expect(testimony).not_to be_valid
      expect(testimony.errors[:bill_news_article]).to include("must belong to the snapshot's bill")
    end

    it "enforces cross-article isolation between text_version and bill_news_article" do
      other_article = create(:news_article, canonical_url: "https://other.com/1")
      other_tv = create(:news_article_text_version, :extracted, news_article: other_article, text: "Verbatim article evidence")
      testimony.news_article_text_version = other_tv

      expect(testimony).not_to be_valid
      expect(testimony.errors[:news_article_text_version]).to include("must belong to the associated bill news article")
    end
  end

  describe "associations" do
    before { testimony.save! }

    it "provides navigation to bill and news_article" do
      expect(testimony.bill).to eq(bill)
      expect(testimony.news_article).to eq(news_article)
    end
  end

  describe "scopes and predicates" do
    let!(:draft_testimony) { create(:news_article_testimony, bill_news_article: bna, news_article_text_version: text_version, publication_state: "draft", stance: "support") }
    let!(:published_testimony) { create(:news_article_testimony, bill_news_article: bna, news_article_text_version: text_version, publication_state: "published", stance: "oppose") }

    it "filters by drafts and published" do
      expect(described_class.drafts).to include(draft_testimony)
      expect(described_class.drafts).not_to include(published_testimony)

      expect(described_class.published).to include(published_testimony)
      expect(described_class.published).not_to include(draft_testimony)
    end

    it "filters by supporting and opposing" do
      expect(described_class.supporting).to include(draft_testimony)
      expect(described_class.supporting).not_to include(published_testimony)

      expect(described_class.opposing).to include(published_testimony)
      expect(described_class.opposing).not_to include(draft_testimony)
    end

    it "provides draft? and published? predicates" do
      expect(draft_testimony.draft?).to be true
      expect(draft_testimony.published?).to be false

      expect(published_testimony.draft?).to be false
      expect(published_testimony.published?).to be true
    end
  end

  describe "#stale? and #currently_eligible?" do
    before { testimony.save! }

    it "is not stale and is currently eligible when fresh and associated article is eligible" do
      expect(testimony.stale?).to be false
      expect(testimony.currently_eligible?).to be true
    end

    it "becomes stale and ineligible when the stance changes" do
      bna.update!(stance: "oppose")
      expect(testimony.stale?).to be true
      expect(testimony.currently_eligible?).to be false
    end

    it "becomes stale and ineligible when stance_version advances" do
      bna.update!(stance_version: bna.stance_version + 1)
      expect(testimony.stale?).to be true
      expect(testimony.currently_eligible?).to be false
    end

    it "becomes stale and ineligible when current_text_version changes" do
      new_tv = create(:news_article_text_version, :extracted, news_article: news_article, text: "Verbatim article evidence newer")
      bna.update!(current_text_version: new_tv)
      expect(testimony.stale?).to be true
      expect(testimony.currently_eligible?).to be false
    end

    it "becomes stale and ineligible when text digest changes" do
      testimony.update_columns(text_digest: "stale_digest_123")
      expect(testimony.stale?).to be true
      expect(testimony.currently_eligible?).to be false
    end

    it "becomes stale and ineligible when review_version advances" do
      bna.update!(review_version: bna.review_version + 1)
      expect(testimony.stale?).to be true
      expect(testimony.currently_eligible?).to be false
    end

    it "becomes stale and ineligible when approval is withdrawn" do
      bna.update!(approved: false)
      expect(testimony.stale?).to be true
      expect(testimony.currently_eligible?).to be false
    end

    it "is not stale but is ineligible when underlying article kind is no longer an op-ed or editorial" do
      news_article.update!(article_kind: "reporting")
      expect(testimony.stale?).to be false
      expect(bna.reload.eligible_for_testimony?).to be false
      expect(testimony.currently_eligible?).to be false
    end

    it "is not stale but is ineligible when underlying text version lacks usable text" do
      NewsArticleTextVersion.where(id: text_version.id).update_all(extraction_status: "failed")
      expect(testimony.stale?).to be false
      expect(bna.reload.eligible_for_testimony?).to be false
      expect(testimony.currently_eligible?).to be false
    end
  end
end
