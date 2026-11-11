# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: news_article_text_versions
# Database name: primary
#
#  id                :integer          not null, primary key
#  digest            :string           not null
#  extraction_status :string           default("extracted"), not null
#  final_url         :string
#  origin            :string           default("retrieved"), not null
#  requested_url     :string
#  text              :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  actor_id          :integer
#  news_article_id   :integer          not null
#
# Indexes
#
#  idx_on_news_article_id_created_at_fd5f7ee9a7                    (news_article_id,created_at)
#  index_news_article_text_versions_on_actor_id                    (actor_id)
#  index_news_article_text_versions_on_digest                      (digest)
#  index_news_article_text_versions_on_news_article_id             (news_article_id)
#  index_news_article_text_versions_on_news_article_id_and_digest  (news_article_id,digest)
#
# Foreign Keys
#
#  actor_id         (actor_id => users.id)
#  news_article_id  (news_article_id => news_articles.id) ON DELETE => restrict
#
RSpec.describe NewsArticleTextVersion, type: :model do
  # @lat: [[news-article-evidence#Immutable article text]]
  let(:news_article) { create(:news_article) }

  describe "mandatory behavioral regression: multi-bill text version isolation and immutability" do
    it "replacing text on one bill leaves the other bill's selected version and all historical versions byte-for-byte intact" do
      sample_text = "City planners presented a 45-page housing density report to council members."
      expected_digest = Digest::SHA256.hexdigest(sample_text)

      bill_1 = create(:bill, scheduled_release_date_utc: 1.day.ago.to_date)
      bill_2 = create(:bill, scheduled_release_date_utc: 2.days.ago.to_date)
      admin = create(:user, :sway_admin)

      version_1 = described_class.create!(
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: sample_text,
        requested_url: news_article.canonical_url,
        final_url: news_article.canonical_url
      )

      bna_1 = create(:bill_news_article, bill: bill_1, news_article: news_article, current_text_version: version_1)
      bna_2 = create(:bill_news_article, bill: bill_2, news_article: news_article, current_text_version: version_1)

      expect(bna_1.current_text_version).to eq(version_1)
      expect(bna_2.current_text_version).to eq(version_1)
      expect(version_1.digest).to eq(expected_digest)

      replacement_text = "Updated manual transcript: Council passed the housing density amendment unanimously."
      replacement_digest = Digest::SHA256.hexdigest(replacement_text)

      version_2 = described_class.create!(
        news_article: news_article,
        origin: "manual",
        extraction_status: "extracted",
        text: replacement_text,
        actor: admin
      )

      bna_1.update!(current_text_version: version_2)

      bna_1.reload
      bna_2.reload
      version_1.reload
      version_2.reload

      expect(bna_1.current_text_version).to eq(version_2)
      expect(bna_1.current_text_version.digest).to eq(replacement_digest)

      expect(bna_2.current_text_version).to eq(version_1)
      expect(bna_2.current_text_version.digest).to eq(expected_digest)

      expect(version_1.text).to eq(sample_text)
      expect(version_1.digest).to eq(expected_digest)
      expect(version_1.origin).to eq("retrieved")

      expect(news_article.text_versions).to contain_exactly(version_1, version_2)
    end
  end

  describe "validations" do
    it "is valid with factory defaults" do
      version = build(:news_article_text_version, news_article:)
      expect(version).to be_valid
    end

    it "requires news_article" do
      version = build(:news_article_text_version, news_article: nil)
      expect(version).not_to be_valid
      expect(version.errors[:news_article]).to be_present
    end

    describe "origin validation" do
      it "requires origin" do
        version = build(:news_article_text_version, news_article:, origin: nil)
        expect(version).not_to be_valid
        expect(version.errors[:origin]).to include("can't be blank")
      end

      it "accepts valid origins: retrieved, manual, admin" do
        %w[retrieved manual admin].each do |valid_origin|
          version = build(:news_article_text_version, news_article:, origin: valid_origin)
          expect(version).to be_valid
        end
      end

      it "rejects invalid origin values" do
        %w[scraped automated third_party invalid].each do |bad_origin|
          version = build(:news_article_text_version, news_article:, origin: bad_origin)
          expect(version).not_to be_valid
          expect(version.errors[:origin]).to be_present
        end
      end
    end

    describe "extraction_status validation" do
      it "requires extraction_status" do
        version = build(:news_article_text_version, news_article:, extraction_status: nil)
        expect(version).not_to be_valid
        expect(version.errors[:extraction_status]).to include("can't be blank")
      end

      it "accepts valid extraction statuses: extracted, paywalled, failed" do
        %w[extracted paywalled failed].each do |valid_status|
          version = build(
            :news_article_text_version,
            news_article:,
            extraction_status: valid_status,
            text: ((valid_status == "extracted") ? "Sample text" : nil)
          )
          expect(version).to be_valid
        end
      end

      it "rejects invalid extraction status values" do
        %w[pending in_progress success error unknown].each do |bad_status|
          version = build(:news_article_text_version, news_article:, extraction_status: bad_status)
          expect(version).not_to be_valid
          expect(version.errors[:extraction_status]).to be_present
        end
      end
    end

    describe "text requirement validation" do
      it "requires text when extraction_status is extracted" do
        version = build(:news_article_text_version, news_article:, extraction_status: "extracted", text: nil)
        expect(version).not_to be_valid
        expect(version.errors[:text]).to include("can't be blank")
      end

      it "requires text when origin is manual" do
        version = build(:news_article_text_version, news_article:, origin: "manual", text: nil, extraction_status: "paywalled")
        expect(version).not_to be_valid
        expect(version.errors[:text]).to include("can't be blank")
      end

      it "allows nil text when paywalled or failed for retrieved origin" do
        paywalled = build(:news_article_text_version, :paywalled, news_article:, origin: "retrieved")
        expect(paywalled).to be_valid

        failed = build(:news_article_text_version, :failed, news_article:, origin: "retrieved")
        expect(failed).to be_valid
      end
    end

    describe "digest validation" do
      it "validates digest format as a 64-character lowercase hex string" do
        version = build(:news_article_text_version, :failed, news_article:, digest: "not-a-sha256")
        expect(version).not_to be_valid
        expect(version.errors[:digest]).to be_present

        valid_version = build(:news_article_text_version, :failed, news_article:, digest: "a" * 64)
        expect(valid_version).to be_valid
      end
    end

    describe "actor association" do
      it "allows actor to be nil for retrieved versions" do
        version = build(:news_article_text_version, :retrieved, news_article:, actor: nil)
        expect(version).to be_valid
      end

      it "allows actor to be a sway admin User for manual versions" do
        admin = create(:user, :sway_admin)
        version = build(:news_article_text_version, :manual, news_article:, actor: admin)
        expect(version).to be_valid
        expect(version.actor).to eq(admin)
      end
    end
  end

  describe "automatic SHA-256 digest computation" do
    it "automatically calculates digest from text before validation when text is present" do
      sample_text = "City planners presented a 45-page housing density report to council members."
      expected_digest = Digest::SHA256.hexdigest(sample_text)

      version = described_class.new(
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: sample_text,
        digest: nil
      )

      expect(version.digest).to be_nil
      expect(version.valid?).to be true
      expect(version.digest).to eq(expected_digest)
    end

    it "recomputes or enforces correct digest even if an incorrect digest is initially passed" do
      sample_text = "City planners presented a 45-page housing density report to council members."
      expected_digest = Digest::SHA256.hexdigest(sample_text)

      version = described_class.new(
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: sample_text,
        digest: "invalid_tampered_digest"
      )

      version.valid?
      expect(version.digest).to eq(expected_digest)
    end

    describe "whitespace payloads" do
      it "computes the exact SHA-256 digest of whitespace strings rather than empty string digest" do
        whitespace_samples = ["   ", "\t\n  "]

        whitespace_samples.each do |ws_payload|
          expected_digest = Digest::SHA256.hexdigest(ws_payload)
          empty_digest = Digest::SHA256.hexdigest("")

          version = described_class.new(
            news_article: news_article,
            origin: "retrieved",
            extraction_status: "paywalled",
            text: ws_payload,
            digest: nil
          )

          expect(version.valid?).to be true
          expect(version.digest).to eq(expected_digest)
          expect(version.digest).not_to eq(empty_digest)
        end
      end

      it "computes the whitespace digest before validation even when extraction_status requires text presence" do
        whitespace_samples = ["   ", "\t\n  "]

        whitespace_samples.each do |ws_payload|
          expected_digest = Digest::SHA256.hexdigest(ws_payload)

          version = described_class.new(
            news_article: news_article,
            origin: "retrieved",
            extraction_status: "extracted",
            text: ws_payload,
            digest: nil
          )

          expect(version.valid?).to be false
          expect(version.errors[:text]).to include("can't be blank")
          expect(version.digest).to eq(expected_digest)
        end
      end

      it "persists the exact whitespace digest to the database on save" do
        whitespace_text = "   \t\n   "
        expected_digest = Digest::SHA256.hexdigest(whitespace_text)

        version = described_class.create!(
          news_article: news_article,
          origin: "retrieved",
          extraction_status: "paywalled",
          text: whitespace_text
        )

        expect(version.reload.digest).to eq(expected_digest)
      end
    end

    describe "tampered digest overwrite" do
      it "overwrites an initial tampered digest with the exact SHA-256 of whitespace text before validation" do
        tampered_digest = "a" * 64
        whitespace_samples = ["   ", "\t\n  "]

        whitespace_samples.each do |ws_payload|
          expected_digest = Digest::SHA256.hexdigest(ws_payload)

          version = described_class.new(
            news_article: news_article,
            origin: "retrieved",
            extraction_status: "paywalled",
            text: ws_payload,
            digest: tampered_digest
          )

          version.valid?

          expect(version.digest).to eq(expected_digest)
          expect(version.digest).not_to eq(tampered_digest)
        end
      end

      it "persists overwritten digest when saved to database for valid combinations with whitespace text" do
        tampered_digest = "a" * 64
        whitespace_samples = ["   ", "\t\n  "]

        whitespace_samples.each do |ws_payload|
          expected_digest = Digest::SHA256.hexdigest(ws_payload)

          version = described_class.create!(
            news_article: news_article,
            origin: "retrieved",
            extraction_status: "paywalled",
            text: ws_payload,
            digest: tampered_digest
          )

          expect(version.reload.digest).to eq(expected_digest)
        end
      end
    end
  end

  describe "immutability" do
    it "marks persisted records as readonly" do
      version = described_class.create!(
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "City planners presented a 45-page housing density report to council members.",
        requested_url: news_article.canonical_url,
        final_url: news_article.canonical_url
      )
      expect(version).to be_readonly
    end

    it "raises ActiveRecord::ReadOnlyRecord when attempting to update text" do
      version = described_class.create!(
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "City planners presented a 45-page housing density report to council members.",
        requested_url: news_article.canonical_url,
        final_url: news_article.canonical_url
      )
      expect {
        version.update(text: "Tampered article text content")
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord when attempting to update! text" do
      version = described_class.create!(
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "City planners presented a 45-page housing density report to council members.",
        requested_url: news_article.canonical_url,
        final_url: news_article.canonical_url
      )
      expect {
        version.update!(text: "Tampered article text content")
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord when attempting to destroy" do
      version = described_class.create!(
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "City planners presented a 45-page housing density report to council members.",
        requested_url: news_article.canonical_url,
        final_url: news_article.canonical_url
      )
      expect {
        version.destroy
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "enums, scopes, and helper methods" do
    describe "origin predicate methods and scopes" do
      it "provides retrieved?, manual?, admin? helpers" do
        retrieved_version = create(:news_article_text_version, :retrieved, :extracted, news_article:)
        manual_version = create(:news_article_text_version, :manual, :extracted, news_article:)
        admin_version = create(:news_article_text_version, :admin, :extracted, news_article:)

        expect(retrieved_version.retrieved?).to be true
        expect(retrieved_version.manual?).to be false
        expect(retrieved_version.admin?).to be false

        expect(manual_version.manual?).to be true
        expect(manual_version.retrieved?).to be false
        expect(manual_version.admin?).to be false

        expect(admin_version.admin?).to be true
        expect(admin_version.manual?).to be false
        expect(admin_version.retrieved?).to be false
      end

      it "provides scopes .retrieved, .manual, and .admin" do
        retrieved_version = create(:news_article_text_version, :retrieved, :extracted, news_article:)
        manual_version = create(:news_article_text_version, :manual, :extracted, news_article:)
        admin_version = create(:news_article_text_version, :admin, :extracted, news_article:)
        paywalled_version = create(:news_article_text_version, :retrieved, :paywalled, news_article:)
        failed_version = create(:news_article_text_version, :retrieved, :failed, news_article:)

        expect(described_class.retrieved).to include(retrieved_version, paywalled_version, failed_version)
        expect(described_class.retrieved).not_to include(manual_version, admin_version)

        expect(described_class.manual).to include(manual_version)
        expect(described_class.manual).not_to include(retrieved_version, admin_version)

        expect(described_class.admin).to include(admin_version)
        expect(described_class.admin).not_to include(retrieved_version, manual_version)
      end
    end

    describe "extraction_status predicate methods and scopes" do
      it "provides extracted?, paywalled?, failed? helpers" do
        retrieved_version = create(:news_article_text_version, :retrieved, :extracted, news_article:)
        paywalled_version = create(:news_article_text_version, :retrieved, :paywalled, news_article:)
        failed_version = create(:news_article_text_version, :retrieved, :failed, news_article:)

        expect(retrieved_version.extracted?).to be true
        expect(paywalled_version.paywalled?).to be true
        expect(failed_version.failed?).to be true
      end

      it "provides scopes .extracted, .paywalled, and .failed" do
        retrieved_version = create(:news_article_text_version, :retrieved, :extracted, news_article:)
        manual_version = create(:news_article_text_version, :manual, :extracted, news_article:)
        admin_version = create(:news_article_text_version, :admin, :extracted, news_article:)
        paywalled_version = create(:news_article_text_version, :retrieved, :paywalled, news_article:)
        failed_version = create(:news_article_text_version, :retrieved, :failed, news_article:)

        expect(described_class.extracted).to include(retrieved_version, manual_version, admin_version)
        expect(described_class.paywalled).to include(paywalled_version)
        expect(described_class.failed).to include(failed_version)
      end
    end

    describe "#usable_text?" do
      it "returns true when text is present and extraction_status is extracted" do
        retrieved_version = create(:news_article_text_version, :retrieved, :extracted, news_article:)
        manual_version = create(:news_article_text_version, :manual, :extracted, news_article:)

        expect(retrieved_version.usable_text?).to be true
        expect(manual_version.usable_text?).to be true
      end

      it "returns false when text is blank or extraction_status is paywalled or failed" do
        paywalled_version = create(:news_article_text_version, :retrieved, :paywalled, news_article:)
        failed_version = create(:news_article_text_version, :retrieved, :failed, news_article:)

        expect(paywalled_version.usable_text?).to be false
        expect(failed_version.usable_text?).to be false
      end
    end
  end
end
