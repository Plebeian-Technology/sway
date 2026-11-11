# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: news_article_source_snapshots
# Database name: primary
#
#  id             :integer          not null, primary key
#  digest         :string           not null
#  purpose        :string           not null
#  run_receipt    :string
#  source_entries :json             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  actor_id       :integer
#  bill_id        :integer          not null
#
# Indexes
#
#  index_news_article_source_snapshots_on_actor_id                (actor_id)
#  index_news_article_source_snapshots_on_bill_id                 (bill_id)
#  index_news_article_source_snapshots_on_bill_id_and_created_at  (bill_id,created_at)
#  index_news_article_source_snapshots_on_bill_id_and_purpose     (bill_id,purpose)
#  index_news_article_source_snapshots_on_digest                  (digest)
#  index_news_article_source_snapshots_on_run_receipt             (run_receipt)
#
# Foreign Keys
#
#  actor_id  (actor_id => users.id) ON DELETE => nullify
#  bill_id   (bill_id => bills.id) ON DELETE => cascade
#
RSpec.describe NewsArticleSourceSnapshot, type: :model do
  # @lat: [[news-article-evidence#Source snapshots and claim uses]]
  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale:) }
  let(:news_article) { create(:news_article) }
  let(:admin) { create(:user, :sway_admin) }

  describe "mandatory behavioral regression: immutable snapshot preservation across review and text changes" do
    it "persists snapshot via NewsArticleSourceSnapshotService, preserving captured text and review state when BillNewsArticle changes" do
      version_1 = create(:news_article_text_version, :extracted, news_article:, text: "Initial reported text: Council approves funding.")
      bna = create(:bill_news_article, :approved, bill:, news_article:, current_text_version: version_1)

      snapshot = NewsArticleSourceSnapshotService.capture!(
        bill:,
        purpose: "summary",
        actor: admin,
        source_uses_attributes: [
          {
            bill_news_article: bna,
            text_version: version_1,
            claim_text: "Housing ordinance introduced in council.",
            evidence_excerpt: "Initial reported text: Council approves funding.",
            citation_url: news_article.canonical_url
          }
        ]
      )

      recorded = BillSummaryRevision.record_revision!(
        bill:,
        summary_markdown: "Council introduced the housing ordinance [Initial reported text: Council approves funding.](https://thebaltimorebanner.com/...).",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        actor: admin,
        news_source_snapshot: snapshot
      )
      revision = BillSummaryRevision.find(Integer(recorded&.id))

      bna.withdraw_approval!(by: admin)
      version_2 = create(:news_article_text_version, :extracted, news_article:, text: "Revised text replacing original: Funding paused.")
      bna.update!(current_text_version: version_2)
      bna.set_stance!("support", by: admin)

      snapshot.reload
      revision.reload

      expect(revision.news_source_snapshot).to eq(snapshot)
      expect(snapshot.captured_text_versions).to contain_exactly(version_1)
      expect(snapshot.captured_text_versions.first.text).to eq("Initial reported text: Council approves funding.")
      expect(snapshot.source_entries.first["review_version"]).to eq(1)
      expect(snapshot.source_entries.first["text_digest"]).to eq(version_1.digest)
      expect(snapshot.source_entries.first["text_version_id"]).to eq(version_1.id)
      expect(snapshot.source_entries.first["approved"]).to be true
      expect(bna.reload.current_text_version).to eq(version_2)

      use = snapshot.news_article_source_uses.first
      expect(use.text_version).to eq(version_1)
      expect(use.evidence_excerpt).to eq("Initial reported text: Council approves funding.")

      comparison = snapshot.current_eligibility_comparison
      expect(comparison.eligible?).to be false
      expect(comparison.stale_reasons).to include(:approval_withdrawn, :text_version_replaced, :stance_changed)
    end

    it "rejects cross-bill source references atomically during snapshot creation" do
      other_bill = create(:bill, sway_locale:)
      foreign_bna = create(:bill_news_article, :approved, :with_text_version, bill: other_bill)

      expect {
        NewsArticleSourceSnapshotService.capture!(
          bill:,
          purpose: "summary",
          source_uses_attributes: [
            {
              bill_news_article: foreign_bna,
              text_version: foreign_bna.current_text_version,
              claim_text: "Claim referencing foreign bill source.",
              evidence_excerpt: foreign_bna.current_text_version.text.truncate(20, omission: ""),
              citation_url: foreign_bna.news_article.canonical_url
            }
          ]
        )
      }.to raise_error(ActiveRecord::RecordInvalid, /must belong to the snapshot's bill/)

      expect {
        NewsArticleSourceSnapshotService.capture!(
          bill:,
          purpose: "summary",
          sources: [foreign_bna]
        )
      }.to raise_error(ArgumentError, /must belong to bill/)
    end
  end

  describe "validations" do
    it "is valid with factory defaults" do
      snapshot = build(:news_article_source_snapshot, bill:)
      expect(snapshot).to be_valid
    end

    it "requires bill" do
      snapshot = build(:news_article_source_snapshot, bill: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:bill]).to be_present
    end

    it "requires purpose to be summary or testimony" do
      %w[summary testimony].each do |valid_purpose|
        expect(build(:news_article_source_snapshot, bill:, purpose: valid_purpose)).to be_valid
      end

      %w[analysis general background invalid].each do |bad_purpose|
        snapshot = build(:news_article_source_snapshot, bill:, purpose: bad_purpose)
        expect(snapshot).not_to be_valid
        expect(snapshot.errors[:purpose]).to be_present
      end
    end

    it "validates digest format" do
      snapshot = build(:news_article_source_snapshot, bill:, digest: "invalid_digest")
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:digest]).to be_present
    end

    it "rejects direct cross-bill source entries" do
      other_bill = create(:bill, sway_locale:)
      foreign_bna = create(:bill_news_article, :approved, :with_text_version, bill: other_bill)

      snapshot = build(
        :news_article_source_snapshot,
        bill:,
        source_entries: [
          {
            "bill_news_article_id" => foreign_bna.id,
            "news_article_id" => foreign_bna.news_article_id
          }
        ]
      )

      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:source_entries]).to include("contains entries from a different bill")
    end
  end

  describe "immutability" do
    let(:snapshot) { create(:news_article_source_snapshot, bill:) }

    it "marks persisted records as readonly" do
      expect(snapshot).to be_readonly
    end

    it "raises ActiveRecord::ReadOnlyRecord on update attempt" do
      expect {
        snapshot.update(purpose: "testimony")
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on update! attempt" do
      expect {
        snapshot.update!(purpose: "testimony")
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on destroy attempt" do
      expect {
        snapshot.destroy
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "scopes and queries" do
    let!(:summary_snap) { create(:news_article_source_snapshot, :summary, bill:) }
    let!(:testimony_snap) { create(:news_article_source_snapshot, :testimony, bill:) }

    it "filters by purpose" do
      expect(described_class.for_summary).to contain_exactly(summary_snap)
      expect(described_class.for_testimony).to contain_exactly(testimony_snap)
    end
  end

  describe "cascade deletion on bill destruction" do
    it "allows deleting a bill with snapshots via dependent: :delete_all" do
      create(:news_article_source_snapshot, bill:)
      expect(bill.news_article_source_snapshots.count).to eq(1)

      expect { bill.destroy! }.not_to raise_error
      expect(described_class.where(bill_id: bill.id).count).to eq(0)
    end

    it "succeeds when bill has bill news articles, snapshots, and source uses, deleting bill evidence while preserving shared articles and text versions" do
      raw_text = "The Baltimore City Council voted unanimously 14-0 on the housing grant initiative."
      text_version = create(
        :news_article_text_version,
        :extracted,
        news_article:,
        text: raw_text
      )
      bna = create(
        :bill_news_article,
        :approved,
        bill:,
        news_article:,
        current_text_version: text_version
      )

      snapshot = NewsArticleSourceSnapshotService.capture!(
        bill:,
        purpose: "summary",
        actor: admin,
        source_uses_attributes: [
          {
            bill_news_article: bna,
            text_version:,
            claim_text: "City council voted 14-0 to approve the initiative.",
            evidence_excerpt: "voted unanimously 14-0",
            citation_url: news_article.canonical_url,
            grounding_status: "supported"
          }
        ]
      )

      revision = BillSummaryRevision.record_revision!(
        bill:,
        summary_markdown: "City council voted 14-0 to approve the initiative [voted unanimously 14-0](#{news_article.canonical_url}).",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        actor: admin,
        news_source_snapshot: snapshot
      )

      bill_id = bill.id
      bna_id = bna.id
      snapshot_id = snapshot.id
      source_use_id = snapshot.source_uses.first.id
      revision_id = Integer(revision&.id)
      article_id = news_article.id
      text_version_id = text_version.id

      expect(bill.bill_news_articles.count).to eq(1)
      expect(bill.news_article_source_snapshots.count).to eq(1)
      expect(snapshot.source_uses.count).to eq(1)
      expect(bill.bill_summary_revisions.where(id: revision_id)).to exist

      expect { bill.destroy! }.not_to raise_error

      expect(Bill.where(id: bill_id)).to be_empty
      expect(BillNewsArticle.where(id: bna_id)).to be_empty
      expect(NewsArticleSourceSnapshot.where(id: snapshot_id)).to be_empty
      expect(NewsArticleSourceUse.where(id: source_use_id)).to be_empty
      expect(BillSummaryRevision.where(id: revision_id)).to be_empty
      expect(BillSummaryRevision.where(bill_id:)).to be_empty

      expect(NewsArticle.where(id: article_id)).to exist
      surviving_article = NewsArticle.find(article_id)
      expect(surviving_article.title).to eq(news_article.title)
      expect(surviving_article.canonical_url).to eq(news_article.canonical_url)

      expect(NewsArticleTextVersion.where(id: text_version_id)).to exist
      surviving_text_version = NewsArticleTextVersion.find(text_version_id)
      expect(surviving_text_version.text).to eq(raw_text)
      expect(surviving_text_version.text&.bytes).to eq(raw_text.bytes)
    end

    it "succeeds when bill_news_articles and source_uses are preloaded in memory without raising RecordNotDestroyed" do
      raw_text = "City budget hearing testimony on renewable energy investment."
      text_version = create(
        :news_article_text_version,
        :extracted,
        news_article:,
        text: raw_text
      )
      bna = create(
        :bill_news_article,
        :approved,
        bill:,
        news_article:,
        current_text_version: text_version
      )

      snapshot = NewsArticleSourceSnapshotService.capture!(
        bill:,
        purpose: "summary",
        actor: admin,
        source_uses_attributes: [
          {
            bill_news_article: bna,
            text_version:,
            claim_text: "Renewable energy investment announced.",
            evidence_excerpt: "renewable energy investment",
            citation_url: news_article.canonical_url,
            grounding_status: "supported"
          }
        ]
      )

      bill_id = bill.id
      bna_id = bna.id
      snapshot_id = snapshot.id
      source_use_id = snapshot.source_uses.first.id
      text_version_id = text_version.id
      article_id = news_article.id

      # Preload associations in memory
      bill.bill_news_articles.load
      bna_in_memory = bill.bill_news_articles.first
      bna_in_memory.source_uses.load
      bna_in_memory.news_article_source_uses.load

      expect(bill.bill_news_articles.loaded?).to be true
      expect(bna_in_memory.source_uses.loaded?).to be true

      expect { bill.destroy! }.not_to raise_error

      expect(Bill.where(id: bill_id)).to be_empty
      expect(BillNewsArticle.where(id: bna_id)).to be_empty
      expect(NewsArticleSourceSnapshot.where(id: snapshot_id)).to be_empty
      expect(NewsArticleSourceUse.where(id: source_use_id)).to be_empty

      expect(NewsArticle.where(id: article_id)).to exist
      expect(NewsArticleTextVersion.where(id: text_version_id)).to exist
      surviving_text_version = NewsArticleTextVersion.find(text_version_id)
      expect(surviving_text_version.text).to eq(raw_text)
      expect(surviving_text_version.text&.bytes).to eq(raw_text.bytes)
    end
  end
end
