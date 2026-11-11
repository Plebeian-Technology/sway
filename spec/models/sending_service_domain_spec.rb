# frozen_string_literal: true

require "rails_helper"

# The learned, operator-confirmed sending-service domain table. A re-run
# must replace a bill's contribution rather than add to it.
# == Schema Information
#
# Table name: sending_service_domains
# Database name: primary
#
#  id              :integer          not null, primary key
#  confirmed_at    :datetime
#  domain          :string           not null
#  label           :string           default("none"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  confirmed_by_id :integer
#
# Indexes
#
#  index_sending_service_domains_on_confirmed_by_id  (confirmed_by_id)
#  index_sending_service_domains_on_domain           (domain) UNIQUE
#
# Foreign Keys
#
#  confirmed_by_id  (confirmed_by_id => users.id)
#
RSpec.describe SendingServiceDomain, type: :model do
  describe "validations" do
    it "saves with a domain and no label" do
      domain = create(:sending_service_domain)
      expect(domain).to be_valid
      expect(domain.label).to eq(SendingServiceDomain::NO_LABEL)
    end

    it "refuses two rows with the same domain" do
      create(:sending_service_domain, domain: "everyactioncustom.com")
      dup = build(:sending_service_domain, domain: "everyactioncustom.com")
      expect(dup.valid?).to be(false)
      expect(dup.errors[:domain]).to be_present
    end

    it "accepts only one of the three label values" do
      domain = build(:sending_service_domain, label: "not_a_real_label")
      expect(domain.valid?).to be(false)
      expect(domain.errors[:label]).to be_present
    end

    it "accepts each of the three declared label values" do
      SendingServiceDomain::LABELS.each do |label|
        domain = build(:sending_service_domain, label: label)
        expect(domain.valid?).to be(true)
      end
    end

    # WR-05. Every row here is derived from a line of a document any member
    # of the public can submit, and every row is shipped on every Bill
    # Creator render. Presence alone let an arbitrarily long run of arbitrary
    # characters become a permanent, globally visible row.
    it "refuses a domain longer than a domain name can be" do
      domain = build(:sending_service_domain, domain: "#{"x" * 250}.com")
      expect(domain.valid?).to be(false)
      expect(domain.errors[:domain]).to be_present
    end

    it "refuses a domain carrying characters a domain name cannot carry" do
      ["a b.com", "<script>.com", "a@b.com", "sp ace", "ünicode.com"].each do |candidate|
        domain = build(:sending_service_domain, domain: candidate)
        expect(domain.valid?).to be(false), "expected #{candidate.inspect} to be refused"
      end
    end

    it "accepts an ordinary sending-service domain" do
      expect(build(:sending_service_domain, domain: "mail-1.everyactioncustom.com").valid?).to be(true)
    end
  end

  describe "confirmation" do
    it "records who confirmed a domain and when" do
      domain = create(:sending_service_domain, :confirmed)
      expect(domain.label).to eq(SendingServiceDomain::CONFIRMED)
      expect(domain.confirmed_by).to be_a(User)
      expect(domain.confirmed_at).to be_present
    end

    it "records neither confirmer nor timestamp for an unlabeled domain" do
      domain = create(:sending_service_domain)
      expect(domain.confirmed_by).to be_nil
      expect(domain.confirmed_at).to be_nil
    end
  end

  describe "summed totals (no running totals on the domain row)" do
    it "reads zero on all three counts when there are no contribution rows" do
      domain = create(:sending_service_domain)
      expect(domain.sender_count).to eq(0)
      expect(domain.letter_count).to eq(0)
      expect(domain.machine_sent_letter_count).to eq(0)
      expect(domain.bill_count).to eq(0)
    end

    it "sums its per-bill contribution rows" do
      domain = create(:sending_service_domain)
      # Two SEPARATE bills, not sharing a locale: bills has a unique index
      # on (scheduled_release_date_utc, sway_locale_id), and the factory's
      # default date is the same for both if they share a locale.
      bill_one = create(:bill)
      bill_two = create(:bill)
      create(:sending_service_domain_bill,
        sending_service_domain: domain, bill: bill_one,
        sender_count: 10, letter_count: 12, machine_sent_letter_count: 9)
      create(:sending_service_domain_bill,
        sending_service_domain: domain, bill: bill_two,
        sender_count: 3, letter_count: 3, machine_sent_letter_count: 0)

      expect(domain.sender_count).to eq(13)
      expect(domain.letter_count).to eq(15)
      expect(domain.machine_sent_letter_count).to eq(9)
      expect(domain.bill_count).to eq(2)
    end

    it "reads machine_sent_share as absent, not zero, when there are no letters" do
      domain = create(:sending_service_domain)
      expect(domain.machine_sent_share).to be_nil
    end

    it "computes machine_sent_share from the summed counts" do
      domain = create(:sending_service_domain)
      create(:sending_service_domain_bill,
        sending_service_domain: domain,
        sender_count: 4, letter_count: 4, machine_sent_letter_count: 3)

      expect(domain.machine_sent_share).to eq(0.75)
    end

    # @lat: [[domain-panel-totals#Why the readers read the attribute rather than call the alias]]
    describe "loaded through .panel_ranked" do
      def sending_service_domain_queries_during
        count = 0
        subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          count += 1 if payload[:sql].to_s.match?(/FROM\s+"sending_service_domain_bills"/i)
        end
        yield
        ActiveSupport::Notifications.unsubscribe(subscription)
        count
      end

      it "reads the same summed counts as a plain load, through the fast path" do
        domain = create(:sending_service_domain)
        bill_one = create(:bill)
        bill_two = create(:bill)
        create(:sending_service_domain_bill,
          sending_service_domain: domain, bill: bill_one,
          sender_count: 10, letter_count: 12, machine_sent_letter_count: 9)
        create(:sending_service_domain_bill,
          sending_service_domain: domain, bill: bill_two,
          sender_count: 3, letter_count: 3, machine_sent_letter_count: 0)

        ranked = SendingServiceDomain.for_panel.panel_ranked.find(domain.id)

        expect(ranked.has_attribute?(:summed_sender_count)).to be(true)
        expect(ranked.respond_to?(:summed_sender_count)).to be(true)
        expect(ranked.sender_count).to eq(13)
        expect(ranked.letter_count).to eq(15)
        expect(ranked.machine_sent_letter_count).to eq(9)
        expect(ranked.bill_count).to eq(2)
      end

      it "takes the alias path without issuing a query, and a plain load still sums" do
        domain = create(:sending_service_domain)
        create(:sending_service_domain_bill,
          sending_service_domain: domain,
          sender_count: 7, letter_count: 9, machine_sent_letter_count: 5)

        ranked = SendingServiceDomain.for_panel.panel_ranked.find(domain.id)
        ranked_queries = sending_service_domain_queries_during { [ranked.sender_count, ranked.letter_count, ranked.bill_count] }

        plain = SendingServiceDomain.find(domain.id)
        expect(plain.has_attribute?(:summed_sender_count)).to be(false)
        plain_queries = sending_service_domain_queries_during { [plain.sender_count, plain.letter_count, plain.bill_count] }

        expect(ranked_queries).to eq(0)
        expect(plain_queries).to eq(3)
        expect([plain.sender_count, plain.letter_count, plain.bill_count]).to eq([7, 9, 1])
      end

      it "computes machine_sent_share correctly from panel_ranked-loaded values" do
        domain = create(:sending_service_domain)
        create(:sending_service_domain_bill,
          sending_service_domain: domain,
          sender_count: 4, letter_count: 4, machine_sent_letter_count: 3)

        ranked = SendingServiceDomain.for_panel.panel_ranked.find(domain.id)

        expect(ranked.machine_sent_share).to eq(0.75)
      end

      it "reads zero, not a string, when a panel_ranked domain has no contribution rows" do
        domain = create(:sending_service_domain, label: SendingServiceDomain::CONFIRMED,
          confirmed_by: create(:user), confirmed_at: Time.zone.now)

        ranked = SendingServiceDomain.for_panel.panel_ranked.find(domain.id)

        expect(ranked.sender_count).to eq(0)
        expect(ranked.letter_count).to eq(0)
        expect(ranked.machine_sent_letter_count).to eq(0)
        expect(ranked.bill_count).to eq(0)
      end

      # machine_sent_share calls .zero? and .to_f on these values — a String back from SQLite's
      # COALESCE(SUM(...)) alias would break both silently (a numeric-looking string is truthy and
      # not zero?, and .to_f on a non-numeric string would just read 0.0 without raising).
      it "hands back real Integers from the SQL-computed aliases, not strings" do
        domain = create(:sending_service_domain)
        create(:sending_service_domain_bill,
          sending_service_domain: domain,
          sender_count: 4, letter_count: 4, machine_sent_letter_count: 3)

        ranked = SendingServiceDomain.for_panel.panel_ranked.find(domain.id)

        expect(ranked.sender_count).to be_a(Integer)
        expect(ranked.letter_count).to be_a(Integer)
        expect(ranked.machine_sent_letter_count).to be_a(Integer)
        expect(ranked.bill_count).to be_a(Integer)
      end
    end
  end
end

# Re-running the cleaning stage must REPLACE a bill's
# contribution row, never add a second one, or a domain's totals climb every
# time an operator tunes a rule and re-runs.
RSpec.describe SendingServiceDomainBill, type: :model do
  describe "validations" do
    it "saves with a domain, a bill and the three counts" do
      expect(create(:sending_service_domain_bill)).to be_valid
    end

    it "refuses two contributions for the same domain and the same bill" do
      domain = create(:sending_service_domain)
      bill = create(:bill)
      create(:sending_service_domain_bill, sending_service_domain: domain, bill: bill)
      dup = build(:sending_service_domain_bill, sending_service_domain: domain, bill: bill)
      expect(dup.valid?).to be(false)
      expect(dup.errors[:bill_id]).to be_present
    end
  end

  describe ".record_contribution!" do
    it "replaces a bill's contribution rather than adding a second one" do
      domain = create(:sending_service_domain)
      bill = create(:bill)

      described_class.record_contribution!(
        sending_service_domain: domain, bill: bill,
        sender_count: 10, letter_count: 12, machine_sent_letter_count: 9
      )
      described_class.record_contribution!(
        sending_service_domain: domain, bill: bill,
        sender_count: 10, letter_count: 12, machine_sent_letter_count: 9
      )

      expect(described_class.where(sending_service_domain: domain, bill: bill).count).to eq(1)
      expect(domain.reload.sender_count).to eq(10)
      expect(domain.letter_count).to eq(12)
      expect(domain.machine_sent_letter_count).to eq(9)
    end

    it "writes the new counts when a rule change alters an existing bill's contribution" do
      domain = create(:sending_service_domain)
      bill = create(:bill)

      described_class.record_contribution!(
        sending_service_domain: domain, bill: bill,
        sender_count: 10, letter_count: 12, machine_sent_letter_count: 9
      )
      described_class.record_contribution!(
        sending_service_domain: domain, bill: bill,
        sender_count: 8, letter_count: 8, machine_sent_letter_count: 8
      )

      expect(described_class.where(sending_service_domain: domain, bill: bill).count).to eq(1)
      expect(domain.reload.sender_count).to eq(8)
    end
  end
end
