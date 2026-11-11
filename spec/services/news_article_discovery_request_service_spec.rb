# frozen_string_literal: true

require "rails_helper"

RSpec.describe NewsArticleDiscoveryRequestService do
  # @lat: [[news-article-evidence#Discovery request receipt]]
  let(:locale) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, sway_locale: locale, status: "committee") }
  let(:admin) { create(:user, :sway_admin) }
  let(:non_admin) { create(:user) }

  describe ".request!" do
    it "creates a queued NewsArticleDiscoveryRequest for admin" do
      req = described_class.request!(bill: bill, requested_by: admin)

      expect(req).to be_persisted
      expect(req.status).to eq("queued")
      expect(req.bill).to eq(bill)
      expect(req.requested_by).to eq(admin)
      expect(req.source_config_digest).to match(/\A[a-f0-9]{64}\z/)
      expect(req.provider).to eq(BraveSearch::Client::PROVIDER_NAME)
      expect(req.model).to eq(BraveSearch::Client::MODEL_NAME)
    end

    it "does not invoke Llm::RouteResolver" do
      expect(Llm::RouteResolver).not_to receive(:resolve)

      req = described_class.request!(bill: bill, requested_by: admin)
      expect(req.provider).to eq("brave_search")
      expect(req.model).to eq("web_search")
    end

    it "raises ArgumentError when requested_by is non-admin or nil" do
      expect {
        described_class.request!(bill: bill, requested_by: non_admin)
      }.to raise_error(ArgumentError, /sway admin/i)

      expect {
        described_class.request!(bill: bill, requested_by: nil)
      }.to raise_error(ArgumentError, /sway admin/i)
    end

    it "raises ArgumentError when bill is not persisted" do
      unpersisted_bill = build(:bill, sway_locale: locale)
      expect {
        described_class.request!(bill: unpersisted_bill, requested_by: admin)
      }.to raise_error(ArgumentError, /persisted bill/i)
    end
  end

  describe ".retry!" do
    it "resets a failed discovery request idempotently" do
      req = described_class.request!(bill: bill, requested_by: admin)
      req.update!(
        status: "failed",
        match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 1, "unmatched" => 2},
        diagnostics: [{"error" => "previous error"}],
        completed_at: Time.current
      )

      retried = described_class.retry!(req)
      expect(retried.id).to eq(req.id)
      expect(retried.status).to eq("queued")
      expect(retried.provider).to eq(BraveSearch::Client::PROVIDER_NAME)
      expect(retried.model).to eq(BraveSearch::Client::MODEL_NAME)
      expect(retried.completed_at).to be_nil
      expect(retried.diagnostics).to eq([])
      expect(retried.match_counts["ambiguous"]).to eq(0)
    end

    it "raises ArgumentError if discovery_request is nil or unpersisted" do
      expect {
        described_class.retry!(nil)
      }.to raise_error(ArgumentError, /persisted/)
    end
  end
end
