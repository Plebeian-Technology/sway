# frozen_string_literal: true

require "rails_helper"

RSpec.describe SetSendingServiceDomainLabelService do
  let(:user) { create(:user) }
  let(:domain) { create(:sending_service_domain, domain: "everyactioncustom.com") }

  describe "#call" do
    it "confirms a domain, recording who and when" do
      outcome = described_class.new(domain: domain, actor: user, label: "confirmed").call

      expect(outcome).to eq(:confirmed)
      domain.reload
      expect(domain.label).to eq(SendingServiceDomain::CONFIRMED)
      expect(domain.confirmed_by).to eq(user)
      expect(domain.confirmed_at).not_to be_nil
    end

    it "removes a label, clearing who confirmed it and when" do
      confirmed_at = 1.day.ago
      domain.update!(label: SendingServiceDomain::CONFIRMED, confirmed_by: user, confirmed_at: confirmed_at)

      outcome = described_class.new(domain: domain, actor: user, label: "none").call

      expect(outcome).to eq(:removed)
      domain.reload
      expect(domain.label).to eq(SendingServiceDomain::NO_LABEL)
      expect(domain.confirmed_by).to be_nil
      expect(domain.confirmed_at).to be_nil
    end

    it "is harmless and changes nothing when a domain already confirmed is confirmed again" do
      original_time = 1.day.ago
      domain.update!(label: SendingServiceDomain::CONFIRMED, confirmed_by: user, confirmed_at: original_time)
      other_user = create(:user)

      outcome = described_class.new(domain: domain, actor: other_user, label: "confirmed").call

      expect(outcome).to eq(:confirmed)
      domain.reload
      expect(domain.label).to eq(SendingServiceDomain::CONFIRMED)
      # The second click never reassigns credit for the first operator's decision.
      expect(domain.confirmed_by).to eq(user)
      expect(domain.confirmed_at).to be_within(1.second).of(original_time)
    end

    it "refuses a label value that is not one of the three known ones" do
      outcome = described_class.new(domain: domain, actor: user, label: "bogus").call

      expect(outcome).to eq(:invalid_label)
      domain.reload
      expect(domain.label).to eq(SendingServiceDomain::NO_LABEL)
    end

    it "refuses 'proposed' and does not un-confirm an already-confirmed domain" do
      confirmed_at = 1.day.ago
      domain.update!(label: SendingServiceDomain::CONFIRMED, confirmed_by: user, confirmed_at: confirmed_at)

      outcome = described_class.new(domain: domain, actor: user, label: "proposed").call

      expect(outcome).to eq(:invalid_label)
      domain.reload
      expect(domain.label).to eq(SendingServiceDomain::CONFIRMED)
      expect(domain.confirmed_by).to eq(user)
      expect(domain.confirmed_at).to be_within(1.second).of(confirmed_at)
    end

    it "can confirm a domain with no contribution rows at all, and its counts read as zero" do
      expect(domain.sending_service_domain_bills).to be_empty

      outcome = described_class.new(domain: domain, actor: user, label: "confirmed").call

      expect(outcome).to eq(:confirmed)
      domain.reload
      expect(domain.sender_count).to eq(0)
      expect(domain.letter_count).to eq(0)
      expect(domain.machine_sent_letter_count).to eq(0)
    end
  end
end
