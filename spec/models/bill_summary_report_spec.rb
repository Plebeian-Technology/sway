# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: bill_summary_reports
# Database name: primary
#
#  id                    :integer          not null, primary key
#  admin_notes           :text
#  details               :text
#  ip_address            :string
#  reason                :string           not null
#  resolved_at           :datetime
#  status                :integer          default("pending"), not null
#  summary_ai_unreviewed :boolean          default(TRUE), not null
#  summary_snapshot      :text
#  user_agent            :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  bill_id               :integer          not null
#  resolved_by_id        :integer
#  user_id               :integer
#
# Indexes
#
#  index_bill_summary_reports_on_bill_id                    (bill_id)
#  index_bill_summary_reports_on_bill_id_and_created_at     (bill_id,created_at)
#  index_bill_summary_reports_on_bill_id_and_status         (bill_id,status)
#  index_bill_summary_reports_on_ip_address_and_created_at  (ip_address,created_at)
#  index_bill_summary_reports_on_resolved_by_id             (resolved_by_id)
#  index_bill_summary_reports_on_status                     (status)
#  index_bill_summary_reports_on_user_id                    (user_id)
#
# Foreign Keys
#
#  bill_id         (bill_id => bills.id) ON DELETE => cascade
#  resolved_by_id  (resolved_by_id => users.id) ON DELETE => nullify
#  user_id         (user_id => users.id) ON DELETE => nullify
#
RSpec.describe BillSummaryReport, type: :model do
  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale:, summary: "Original bill summary text.") }
  let(:user) { create(:user) }

  describe "validations and enums" do
    it "is valid with valid attributes" do
      report = build(:bill_summary_report, bill:, user:)
      expect(report).to be_valid
    end

    it "requires a reason" do
      report = build(:bill_summary_report, bill:, reason: nil)
      expect(report).not_to be_valid
      expect(report.errors[:reason]).to be_present
    end

    it "validates reason inclusion in VALID_REASONS" do
      valid_reasons = %w[factual_inaccuracy misleading_tone missing_amendment other]
      valid_reasons.each do |r|
        report = build(:bill_summary_report, bill:, reason: r)
        expect(report).to be_valid
      end

      report = build(:bill_summary_report, bill:, reason: "not_a_real_reason")
      expect(report).not_to be_valid
      expect(report.errors[:reason]).to be_present
    end

    it "validates details length max 2000 chars" do
      report = build(:bill_summary_report, bill:, details: "a" * 2001)
      expect(report).not_to be_valid
      expect(report.errors[:details]).to be_present

      report.details = "a" * 2000
      expect(report).to be_valid
    end

    it "supports status transitions" do
      report = create(:bill_summary_report, bill:)
      expect(report.status).to eq("pending")
      expect(report).to be_pending

      report.reviewed!
      expect(report).to be_reviewed

      report.resolved!
      expect(report).to be_resolved

      report.dismissed!
      expect(report).to be_dismissed
    end
  end

  describe "callbacks and snapshots" do
    it "captures bill summary snapshot and unreviewed flag on creation" do
      create(:bill_llm_provisioning, bill:, llm_summary: bill.summary)
      expect(bill.summary_ai_unreviewed?).to be(true)

      report = create(:bill_summary_report, bill:)
      expect(report.summary_snapshot).to eq("Original bill summary text.")
      expect(report.summary_ai_unreviewed).to be(true)
    end
  end

  describe "duplicate report throttling" do
    it "throttles duplicate pending reports for same bill from same authenticated user" do
      create(:bill_summary_report, bill:, user:)
      duplicate = build(:bill_summary_report, bill:, user:)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base]).to include("A report for this bill summary was already submitted recently. Thank you for your feedback.")
    end

    it "throttles duplicate pending reports for same bill from same anonymous IP" do
      create(:bill_summary_report, bill:, user: nil, ip_address: "192.168.1.100")
      duplicate = build(:bill_summary_report, bill:, user: nil, ip_address: "192.168.1.100")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base]).to include("A report for this bill summary was already submitted recently. Thank you for your feedback.")
    end

    it "allows a new report if previous report was already resolved or dismissed" do
      first = create(:bill_summary_report, bill:, user:)
      first.resolved!

      second = build(:bill_summary_report, bill:, user:)
      expect(second).to be_valid
    end

    it "allows reports from the same user on different bills" do
      other_bill = create(:bill, sway_locale:, scheduled_release_date_utc: 2.days.ago)
      create(:bill_summary_report, bill:, user:)

      second = build(:bill_summary_report, bill: other_bill, user:)
      expect(second).to be_valid
    end

    it "enforces the 24-hour boundary and does not throttle different authenticated users sharing a NAT IP" do
      recent = create(:bill_summary_report, bill:, user:, status: :reviewed, ip_address: "203.0.113.42")
      recent.update_column(:created_at, (24.hours - 5.minutes).ago)
      expect(build(:bill_summary_report, bill:, user:, reason: "misleading_tone")).not_to be_valid

      second_user = create(:user)
      expect(build(:bill_summary_report, bill:, user: second_user, ip_address: "203.0.113.42")).to be_valid

      recent.update_column(:created_at, (24.hours + 5.minutes).ago)
      expect(build(:bill_summary_report, bill:, user:, reason: "misleading_tone")).to be_valid
    end
  end

  describe "display helpers" do
    it "identifies anonymous vs authenticated reporters" do
      anon = build(:bill_summary_report, user: nil)
      expect(anon).to be_anonymous
      expect(anon.reporter_display_name).to eq("Anonymous Reader")

      user.update!(full_name: "Jane Voter")
      auth = build(:bill_summary_report, user:)
      expect(auth).not_to be_anonymous
      expect(auth.reporter_display_name).to eq("Jane Voter")
    end

    it "returns humanized reason label" do
      report = build(:bill_summary_report, reason: "factual_inaccuracy")
      expect(report.reason_label).to eq("Factual Inaccuracy")
    end
  end
end
