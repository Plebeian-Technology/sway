# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: news_articles
# Database name: primary
#
#  id            :integer          not null, primary key
#  article_kind  :string           default("unknown"), not null
#  author_name   :string
#  canonical_url :string           not null
#  outlet_name   :string           not null
#  published_at  :datetime
#  title         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_news_articles_on_canonical_url  (canonical_url) UNIQUE
#  index_news_articles_on_outlet_name    (outlet_name)
#  index_news_articles_on_published_at   (published_at)
#
RSpec.describe NewsArticle, type: :model do
  # @lat: [[news-article-evidence#Article identity and bill association]]
  describe "validations" do
    it "is valid with standard factory attributes" do
      article = build(:news_article)
      expect(article).to be_valid
    end

    describe "canonical_url validations" do
      it "requires canonical_url" do
        article = build(:news_article, canonical_url: nil)
        expect(article).not_to be_valid
        expect(article.errors[:canonical_url]).to include("can't be blank")
      end

      it "enforces uniqueness of canonical_url" do
        create(:news_article, canonical_url: "https://example.com/unique-story")
        duplicate = build(:news_article, canonical_url: "https://example.com/unique-story")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:canonical_url]).to include("has already been taken")
      end

      it "accepts valid https URLs" do
        article = build(:news_article, canonical_url: "https://example.com/story-123")
        expect(article).to be_valid
      end

      it "rejects malformed URLs or non-https schemes" do
        ["not-a-url", "ftp://example.com/file", "javascript:alert(1)", "http://example.com/insecure"].each do |bad_url|
          article = build(:news_article, canonical_url: bad_url)
          expect(article).not_to be_valid
          expect(article.errors[:canonical_url]).to be_present
        end
      end

      it "provides url as an alias for canonical_url" do
        article = build(:news_article, canonical_url: "https://example.com/story-alias")
        expect(article.url).to eq("https://example.com/story-alias")

        article.url = "https://example.com/story-updated"
        expect(article.canonical_url).to eq("https://example.com/story-updated")
      end
    end

    describe "title and outlet_name validations" do
      it "requires title" do
        article = build(:news_article, title: nil)
        expect(article).not_to be_valid
        expect(article.errors[:title]).to include("can't be blank")
      end

      it "requires outlet_name" do
        article = build(:news_article, outlet_name: nil)
        expect(article).not_to be_valid
        expect(article.errors[:outlet_name]).to include("can't be blank")
      end
    end

    describe "optional attributes" do
      it "allows author_name and published_at to be nil" do
        article = build(:news_article, author_name: nil, published_at: nil)
        expect(article).to be_valid
      end
    end

    describe "article_kind validation" do
      it "allows valid kinds: reporting, op_ed, editorial, unknown" do
        %w[reporting op_ed editorial unknown].each do |kind|
          article = build(:news_article, article_kind: kind)
          expect(article).to be_valid
        end
      end

      it "rejects invalid article_kind" do
        article = build(:news_article, article_kind: "tabloid_gossip")
        expect(article).not_to be_valid
        expect(article.errors[:article_kind]).to be_present
      end

      it "defaults article_kind to unknown" do
        article = described_class.new
        expect(article.article_kind).to eq("unknown")
      end
    end
  end

  describe "associations" do
    it "has many bill_news_articles" do
      article = create(:news_article)
      bill = create(:bill, scheduled_release_date_utc: 1.day.ago.to_date)
      bna = create(:bill_news_article, news_article: article, bill:)

      expect(article.bill_news_articles).to include(bna)
    end

    it "has many bills through bill_news_articles" do
      article = create(:news_article)
      bill_1 = create(:bill, scheduled_release_date_utc: 1.day.ago.to_date)
      bill_2 = create(:bill, scheduled_release_date_utc: 2.days.ago.to_date)
      create(:bill_news_article, news_article: article, bill: bill_1)
      create(:bill_news_article, news_article: article, bill: bill_2)

      expect(article.bills).to contain_exactly(bill_1, bill_2)
    end

    it "restricts deletion when referenced by bill_news_articles" do
      article = create(:news_article)
      bill = create(:bill, scheduled_release_date_utc: 1.day.ago.to_date)
      create(:bill_news_article, news_article: article, bill:)

      expect(article.destroy).to be false
      expect(article.errors[:base]).to be_present
      expect(NewsArticle.exists?(article.id)).to be true
    end

    it "has many text_versions with dependent: :restrict_with_error" do
      article = create(:news_article)
      version = create(:news_article_text_version, news_article: article)

      expect(article.text_versions).to include(version)

      expect(article.destroy).to be false
      expect(article.errors[:base]).to be_present
      expect(NewsArticle.exists?(article.id)).to be true
    end
  end
end
