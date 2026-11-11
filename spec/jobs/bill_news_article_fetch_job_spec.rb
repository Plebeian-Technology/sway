# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillNewsArticleFetchJob do
  # @lat: [[news-article-evidence#Discovery request receipt]]
  # @lat: [[llm-summaries#Batch summarisation]]
  describe "class macros" do
    it "is configured for the :background queue" do
      expect(described_class.queue_name).to eq("background")
    end

    it "uses :polynomially_longer retry (NOT :exponentially_longer)" do
      source = Rails.root.join("app", "jobs", "bill_news_article_fetch_job.rb").read
      expect(source).to include(":polynomially_longer")
      expect(source).not_to include(":exponentially_longer")
    end

    it "has limits_concurrency with on_conflict: :discard" do
      source = Rails.root.join("app", "jobs", "bill_news_article_fetch_job.rb").read
      expect(source).to include("limits_concurrency")
      expect(source).to include("on_conflict: :discard")
      expect(source).to match(/key:\s*->\(bill_id/)
    end
  end

  describe "#perform" do
    let(:bill) { create(:bill) }
    let(:admin) { create(:user, :sway_admin) }
    let(:non_admin) { create(:user) }

    it "calls BillNewsArticleFetchService.call with bill and sway-admin user" do
      expect(BillNewsArticleFetchService).to receive(:call)
        .with(bill: bill, requested_by: admin, discovery_request: nil)
      described_class.new.perform(bill.id, admin.id)
    end

    it "passes discovery_request when provided" do
      request = NewsArticleDiscoveryRequest.create!(
        bill: bill,
        requested_by: admin,
        status: "queued",
        source_config_digest: Digest::SHA256.hexdigest("mock"),
        provider: "claude",
        model: "claude-haiku-5-5"
      )

      expect(BillNewsArticleFetchService).to receive(:call)
        .with(bill: bill, requested_by: admin, discovery_request: request)
      described_class.new.perform(bill.id, admin.id, request.id)
    end

    it "returns nil and does not call service if bill is not found" do
      expect(BillNewsArticleFetchService).not_to receive(:call)
      expect { described_class.new.perform(-999, admin.id) }.not_to raise_error
    end

    it "returns nil and does not call service if requested_by is missing or non-admin" do
      expect(BillNewsArticleFetchService).not_to receive(:call)
      described_class.new.perform(bill.id, nil)
      described_class.new.perform(bill.id, non_admin.id)
    end

    it "aborts and does not call service when discovery_request_id belongs to a different bill" do
      other_bill = create(:bill)
      mismatched_request = create(:news_article_discovery_request, bill: other_bill, requested_by: admin)

      expect(BillNewsArticleFetchService).not_to receive(:call)
      described_class.new.perform(bill.id, admin.id, mismatched_request.id)
    end

    it "aborts and does not call service when discovery_request_id was requested by a different user" do
      other_admin = create(:user, :sway_admin)
      mismatched_request = create(:news_article_discovery_request, bill: bill, requested_by: other_admin)

      expect(BillNewsArticleFetchService).not_to receive(:call)
      described_class.new.perform(bill.id, admin.id, mismatched_request.id)
    end

    it "enqueues NewsArticleTextFetchJob for candidate articles lacking current_text_version on discovery success" do
      news_article = create(:news_article)
      bna = create(:bill_news_article, bill: bill, news_article: news_article, current_text_version: nil)
      receipt = instance_double(NewsArticleDiscoveryRequest, status: "succeeded")

      allow(BillNewsArticleFetchService).to receive(:call).and_return(receipt)
      expect(NewsArticleTextFetchJob).to receive(:perform_later).with(bna.id)

      described_class.new.perform(bill.id, admin.id)
    end

    it "does not enqueue NewsArticleTextFetchJob when discovery status is not succeeded" do
      receipt = instance_double(NewsArticleDiscoveryRequest, status: "failed")
      allow(BillNewsArticleFetchService).to receive(:call).and_return(receipt)

      expect(NewsArticleTextFetchJob).not_to receive(:perform_later)
      described_class.new.perform(bill.id, admin.id)
    end

    it "does not enqueue NewsArticleTextFetchJob for candidate articles that already have a current text version" do
      news_article = create(:news_article)
      text_version = create(:news_article_text_version, news_article: news_article)
      create(:bill_news_article, bill: bill, news_article: news_article, current_text_version: text_version)
      receipt = instance_double(NewsArticleDiscoveryRequest, status: "succeeded")

      allow(BillNewsArticleFetchService).to receive(:call).and_return(receipt)
      expect(NewsArticleTextFetchJob).not_to receive(:perform_later)

      described_class.new.perform(bill.id, admin.id)
    end
  end
end
