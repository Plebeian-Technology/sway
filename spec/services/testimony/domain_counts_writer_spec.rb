# frozen_string_literal: true

require "rails_helper"

# Writes each bill's contribution to the learned
# sending-service-domain counts, replacing what was there, so a re-run cannot
# inflate the counts as an operator tunes a rule.
# Sets no label anywhere; the label is an operator's decision on a later
# plan's screen.
RSpec.describe Testimony::DomainCountsWriter do
  let(:bill) { create(:bill) }

  def domain_letter(position:, domain:, address:, campaign_origin: false, repeat: false)
    {
      "position" => position,
      "sender_address" => address,
      "sender_domain" => domain,
      "campaign_origin" => campaign_origin,
      "repeat" => repeat
    }
  end

  describe ".call" do
    # B2. The on-ramp is built from a document any member of the public can
    # submit: LetterSplitter cuts a new letter at every line-initial "From:",
    # so N From: lines create up to N global rows. There was no off-ramp at
    # all — a SendingServiceDomain was created and never deleted, so a row
    # nobody had ever labelled outlived the only bill that named it and went
    # on being shipped on every Bill Creator render, reading "0 senders,
    # 0 bills, 0%" with a Confirm button beside it.
    it "deletes an unlabelled domain once the re-run stops naming it" do
      described_class.call(bill: bill, letters: [
        domain_letter(position: 0, domain: "gone.example.com", address: "a@gone.example.com")
      ])
      expect(SendingServiceDomain.find_by(domain: "gone.example.com")).to be_present

      described_class.call(bill: bill, letters: [
        domain_letter(position: 0, domain: "stays.example.com", address: "a@stays.example.com")
      ])

      expect(SendingServiceDomain.find_by(domain: "gone.example.com")).to be_nil
      expect(SendingServiceDomain.find_by(domain: "stays.example.com")).to be_present
    end

    # A label is an operator's decision and outlives the contributions that
    # prompted it. Only an unlabelled row with nothing pointing at it is
    # nobody's decision, which is exactly the residue an untrusted PDF leaves.
    it "keeps a domain an operator has labelled even when nothing names it any more" do
      described_class.call(bill: bill, letters: [
        domain_letter(position: 0, domain: "confirmed.example.com", address: "a@confirmed.example.com")
      ])
      SendingServiceDomain.find_by!(domain: "confirmed.example.com")
        .update!(label: SendingServiceDomain::CONFIRMED)

      described_class.call(bill: bill, letters: [])

      kept = SendingServiceDomain.find_by(domain: "confirmed.example.com")
      expect(kept).to be_present
      expect(kept.letter_count).to eq(0)
    end

    it "writes one domain row and one contribution row per distinct sender domain in the bill" do
      letters = [
        domain_letter(position: 0, domain: "campaign-tool.example.com", address: "one@campaign-tool.example.com", campaign_origin: true),
        domain_letter(position: 1, domain: "campaign-tool.example.com", address: "two@campaign-tool.example.com", campaign_origin: true),
        domain_letter(position: 2, domain: "gmail.com", address: "three@gmail.com")
      ]

      described_class.call(bill: bill, letters: letters)

      tool_domain = SendingServiceDomain.find_by(domain: "campaign-tool.example.com")
      expect(tool_domain).to be_present
      expect(tool_domain.sender_count).to eq(2)
      expect(tool_domain.letter_count).to eq(2)
      expect(tool_domain.machine_sent_letter_count).to eq(2)

      gmail_domain = SendingServiceDomain.find_by(domain: "gmail.com")
      expect(gmail_domain).to be_present
      expect(gmail_domain.sender_count).to eq(1)
      expect(gmail_domain.machine_sent_letter_count).to eq(0)
    end

    # @lat: [[testimony-letters#The same letter can arrive twice]]
    it "excludes a repeat letter from a domain's letter_count and sender_count" do
      letters = [
        domain_letter(position: 0, domain: "campaign-tool.example.com", address: "one@campaign-tool.example.com", campaign_origin: true),
        domain_letter(position: 1, domain: "campaign-tool.example.com", address: "one@campaign-tool.example.com", campaign_origin: true, repeat: true)
      ]

      described_class.call(bill: bill, letters: letters)

      domain = SendingServiceDomain.find_by(domain: "campaign-tool.example.com")
      expect(domain.letter_count).to eq(1)
      expect(domain.sender_count).to eq(1)
      expect(domain.machine_sent_letter_count).to eq(1)
    end

    it "sets no label on any domain — the writer records counts only, an operator decides the label later" do
      letters = [domain_letter(position: 0, domain: "campaign-tool.example.com", address: "one@campaign-tool.example.com")]

      described_class.call(bill: bill, letters: letters)

      domain = SendingServiceDomain.find_by(domain: "campaign-tool.example.com")
      expect(domain.label).to eq(SendingServiceDomain::NO_LABEL)
    end

    it "leaves a domain's totals unchanged when the stage runs twice on the same bill" do
      letters = [
        domain_letter(position: 0, domain: "campaign-tool.example.com", address: "one@campaign-tool.example.com", campaign_origin: true),
        domain_letter(position: 1, domain: "campaign-tool.example.com", address: "two@campaign-tool.example.com", campaign_origin: true)
      ]

      described_class.call(bill: bill, letters: letters)
      first_run_count = SendingServiceDomain.find_by(domain: "campaign-tool.example.com").letter_count

      described_class.call(bill: bill, letters: letters)
      second_run_count = SendingServiceDomain.find_by(domain: "campaign-tool.example.com").letter_count

      expect(second_run_count).to eq(first_run_count)
      expect(
        SendingServiceDomainBill.where(bill: bill, sending_service_domain: SendingServiceDomain.find_by(domain: "campaign-tool.example.com")).count
      ).to eq(1)
    end

    it "grows a domain's totals when a second bill contributes to it" do
      other_bill = create(:bill)
      letters = [domain_letter(position: 0, domain: "campaign-tool.example.com", address: "one@campaign-tool.example.com", campaign_origin: true)]

      described_class.call(bill: bill, letters: letters)
      described_class.call(bill: other_bill, letters: letters)

      domain = SendingServiceDomain.find_by(domain: "campaign-tool.example.com")
      expect(domain.letter_count).to eq(2)
      expect(domain.sender_count).to eq(2)
    end

    it "drops a bill's contribution row for a domain that appeared on an earlier run but not on this one" do
      first_run_letters = [
        domain_letter(position: 0, domain: "campaign-tool.example.com", address: "one@campaign-tool.example.com"),
        domain_letter(position: 1, domain: "gmail.com", address: "two@gmail.com")
      ]
      described_class.call(bill: bill, letters: first_run_letters)

      second_run_letters = [domain_letter(position: 0, domain: "campaign-tool.example.com", address: "one@campaign-tool.example.com")]
      described_class.call(bill: bill, letters: second_run_letters)

      gmail_domain = SendingServiceDomain.find_by(domain: "gmail.com")
      expect(SendingServiceDomainBill.where(bill: bill, sending_service_domain: gmail_domain)).to be_empty
    end

    it "writes nothing and does not raise when no letter carries a domain" do
      expect { described_class.call(bill: bill, letters: []) }.not_to raise_error
      expect(SendingServiceDomainBill.where(bill: bill)).to be_empty
    end

    # CR-02. Testimony::SenderReader no longer produces these, but an
    # artifact written before it stopped is still stored and still read on
    # every re-run, and one empty domain in it raised RecordInvalid and
    # failed the stage for that bill permanently. The writer is the last
    # place that can refuse it.
    it "skips a letter whose stored domain is empty, rather than failing the whole stage" do
      letters = [
        domain_letter(position: 0, domain: "", address: "someone@"),
        domain_letter(position: 1, domain: "gmail.com", address: "two@gmail.com")
      ]

      expect { described_class.call(bill: bill, letters: letters) }.not_to raise_error
      expect(SendingServiceDomain.pluck(:domain)).to eq(["gmail.com"])
    end

    it "skips a stored domain that is not shaped like a domain name" do
      letters = [
        domain_letter(position: 0, domain: "x" * 300, address: "someone@#{"x" * 300}"),
        domain_letter(position: 1, domain: "gmail.com", address: "two@gmail.com")
      ]

      described_class.call(bill: bill, letters: letters)

      expect(SendingServiceDomain.pluck(:domain)).to eq(["gmail.com"])
    end

    it "skips excluded letters when recording domain contributions" do
      letters = [
        domain_letter(position: 0, domain: "excluded.example.com", address: "one@excluded.example.com").merge("excluded" => true),
        domain_letter(position: 1, domain: "gmail.com", address: "two@gmail.com")
      ]

      described_class.call(bill: bill, letters: letters)

      expect(SendingServiceDomain.find_by(domain: "excluded.example.com")).to be_nil
      expect(SendingServiceDomain.find_by!(domain: "gmail.com").letter_count).to eq(1)
    end
  end
end
