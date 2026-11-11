# frozen_string_literal: true

require "rails_helper"

RSpec.describe NewsArticleTextFetchJob do
  # @lat: [[news-article-evidence#Discovery request receipt]]
  # @lat: [[news-article-evidence#Immutable article text]]
  describe "class macros" do
    it "is configured for the :background queue" do
      expect(described_class.queue_name).to eq("background")
    end

    it "uses :polynomially_longer retry" do
      source = Rails.root.join("app", "jobs", "news_article_text_fetch_job.rb").read
      expect(source).to include(":polynomially_longer")
      expect(source).not_to include(":exponentially_longer")
    end

    it "has limits_concurrency with on_conflict: :discard" do
      source = Rails.root.join("app", "jobs", "news_article_text_fetch_job.rb").read
      expect(source).to include("limits_concurrency")
      expect(source).to include("on_conflict: :discard")
      expect(source).to match(/key:\s*->\(bill_news_article_id/)
    end
  end

  describe "#perform" do
    let(:bill) { create(:bill) }
    let(:news_article) { create(:news_article) }
    let(:bill_news_article) { create(:bill_news_article, bill: bill, news_article: news_article) }

    it "invokes NewsArticleTextFetchService.call with the specified bill_news_article" do
      expect(NewsArticleTextFetchService).to receive(:call).with(bill_news_article: bill_news_article)
      described_class.new.perform(bill_news_article.id)
    end

    it "handles missing bill_news_article gracefully without calling the service" do
      expect(NewsArticleTextFetchService).not_to receive(:call)
      expect { described_class.new.perform(-999) }.not_to raise_error
    end
  end
end
