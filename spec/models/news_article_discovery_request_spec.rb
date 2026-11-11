# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: news_article_discovery_requests
# Database name: primary
#
#  id                   :integer          not null, primary key
#  completed_at         :datetime
#  diagnostics          :json             not null
#  match_counts         :json             not null
#  model                :string           not null
#  provider             :string           not null
#  query                :text
#  source_config_digest :string           not null
#  status               :string           default("queued"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  bill_id              :integer          not null
#  requested_by_id      :integer          not null
#
# Indexes
#
#  idx_on_bill_id_created_at_5965be0083                         (bill_id,created_at)
#  index_news_article_discovery_requests_on_bill_id             (bill_id)
#  index_news_article_discovery_requests_on_bill_id_and_status  (bill_id,status)
#  index_news_article_discovery_requests_on_requested_by_id     (requested_by_id)
#  index_news_article_discovery_requests_on_status              (status)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id) ON DELETE => cascade
#  requested_by_id  (requested_by_id => users.id) ON DELETE => restrict
#
RSpec.describe NewsArticleDiscoveryRequest do
  # @lat: [[news-article-evidence#Discovery request receipt]]
  let(:locale) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, sway_locale: locale) }
  let(:admin) { create(:user, :sway_admin) }
  let(:non_admin) { create(:user) }
  let(:valid_digest) { Digest::SHA256.hexdigest("sample-config") }

  subject(:request) do
    described_class.new(
      bill: bill,
      requested_by: admin,
      status: "queued",
      source_config_digest: valid_digest,
      provider: "claude",
      model: "claude-haiku-5-5",
      match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0},
      diagnostics: []
    )
  end

  describe "validations and associations" do
    it "is valid with valid attributes" do
      expect(request).to be_valid
    end

    it "belongs to bill" do
      expect(request.bill).to eq(bill)
    end

    it "belongs to requested_by (User)" do
      expect(request.requested_by).to eq(admin)
    end

    it "requires a bill" do
      request.bill = nil
      expect(request).not_to be_valid
      expect(request.errors[:bill]).to be_present
    end

    it "requires requested_by" do
      request.requested_by = nil
      expect(request).not_to be_valid
      expect(request.errors[:requested_by]).to be_present
    end

    it "enforces that requested_by must be a sway admin" do
      request.requested_by = non_admin
      expect(request).not_to be_valid
      expect(request.errors[:requested_by]).to include("must be a Sway admin")
    end

    it "validates status inclusion" do
      described_class::STATUSES.each do |st|
        request.status = st
        expect(request).to be_valid
      end

      request.status = "invalid_status"
      expect(request).not_to be_valid
      expect(request.errors[:status]).to be_present
    end

    it "validates source_config_digest presence and SHA256 format" do
      request.source_config_digest = nil
      expect(request).not_to be_valid

      request.source_config_digest = "not-a-valid-sha256"
      expect(request).not_to be_valid

      request.source_config_digest = valid_digest
      expect(request).to be_valid
    end

    it "validates provider presence" do
      request.provider = nil
      expect(request).not_to be_valid
      expect(request.errors[:provider]).to be_present
    end

    it "validates model presence" do
      request.model = nil
      expect(request).not_to be_valid
      expect(request.errors[:model]).to be_present
    end
  end

  describe "status predicates and scopes" do
    it "correctly identifies terminal vs non-terminal statuses" do
      %w[queued running].each do |st|
        request.status = st
        expect(request).not_to be_terminal
      end

      %w[succeeded no_matches partial_failure failed unsupported].each do |st|
        request.status = st
        expect(request).to be_terminal
      end
    end

    it "provides specific status predicate methods" do
      request.status = "succeeded"
      expect(request.succeeded?).to be true
      expect(request.failed?).to be false

      request.status = "no_matches"
      expect(request.no_matches?).to be true

      request.status = "unsupported"
      expect(request.unsupported?).to be true

      request.status = "failed"
      expect(request.failed?).to be true

      request.status = "partial_failure"
      expect(request.partial_failure?).to be true

      request.status = "running"
      expect(request.running?).to be true

      request.status = "queued"
      expect(request.queued?).to be true
    end

    it "filters via .terminal and .active scopes" do
      request.save!
      active_req = request
      term_req = described_class.create!(
        bill: bill,
        requested_by: admin,
        status: "succeeded",
        source_config_digest: valid_digest,
        provider: "claude",
        model: "claude-haiku-5-5"
      )

      expect(described_class.active).to include(active_req)
      expect(described_class.active).not_to include(term_req)
      expect(described_class.terminal).to include(term_req)
      expect(described_class.terminal).not_to include(active_req)
    end
  end

  describe "bill and user deletion lifecycles" do
    it "cascades delete when the bill is destroyed" do
      request.save!
      expect { bill.destroy! }.to change(described_class, :count).by(-1)
    end

    it "restricts deletion of the requested_by user while requests exist" do
      request.save!
      expect { admin.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end
  end
end
