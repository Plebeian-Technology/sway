# == Schema Information
#
# Table name: user_legislator_emails
# Database name: primary
#
#  id                 :integer          not null, primary key
#  status             :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  bill_id            :integer          not null
#  user_legislator_id :integer          not null
#
# Indexes
#
#  index_user_legislator_emails_on_bill_id             (bill_id)
#  index_user_legislator_emails_on_ul_and_bill         (user_legislator_id,bill_id) UNIQUE
#  index_user_legislator_emails_on_user_legislator_id  (user_legislator_id)
#
# Foreign Keys
#
#  bill_id             (bill_id => bills.id)
#  user_legislator_id  (user_legislator_id => user_legislators.id)
#
require "rails_helper"

RSpec.describe UserLegislatorEmail, type: :model do
  describe "associations" do
    it "persists with a user_legislator and bill via factory" do
      record = create(:user_legislator_email)
      expect(record).to be_persisted
      expect(record.user_legislator).to be_a(UserLegislator)
      expect(record.bill).to be_a(Bill)
    end

    it "delegates legislator, user, and sway_locale through its associations" do
      record = create(:user_legislator_email)
      expect(record.legislator).to eq(record.user_legislator.legislator)
      expect(record.user).to eq(record.user_legislator.user)
      expect(record.sway_locale).to eq(record.bill.sway_locale)
    end

    it "is invalid without a bill (belongs_to :bill is required)" do
      record = build(:user_legislator_email, bill: nil)
      expect(record).not_to be_valid
      expect(record.errors[:bill]).to be_present
    end
  end

  describe "status enum" do
    it "defaults to :pending" do
      record = create(:user_legislator_email)
      expect(record.status).to eq("pending")
      expect(record.pending?).to be(true)
    end

    it "supports transitioning to sending, sent, and failed via update" do
      record = create(:user_legislator_email)
      record.update!(status: :sent)
      expect(record.sent?).to be(true)
      record.update!(status: :failed)
      expect(record.failed?).to be(true)
    end
  end

  describe "#sendable?" do
    # @lat: [[bill-session-archiving-tests#Bill session archive tests#Queued outreach skips archives]]
    it "does not send outreach for a bill archived after the email was queued" do
      record = create(:user_legislator_email)
      record.bill.update!(archived_at: Time.current)
      expect(record.sendable?).to eq(false)
    end

    it "is false when RESEND_EMAIL_API_KEY is not set" do
      record = create(:user_legislator_email)
      if defined?(ClimateControl)
        ClimateControl.modify(RESEND_EMAIL_API_KEY: nil) do
          expect(record.sendable?).to be_falsey
        end
      end

      # If ClimateControl is not loaded, fake the ENV lookup directly instead.
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("RESEND_EMAIL_API_KEY").and_return(nil)
      expect(record.sendable?).to be_falsey
    end
  end

  # The database index across (user_legislator_id, bill_id) is what makes the
  # controller's create_or_find_by safe: a double-click cannot slip in a second row and
  # send the legislator the same email twice.
  describe "(user_legislator_id, bill_id) uniqueness" do
    it "rejects a duplicate email row for one user_legislator + bill" do
      existing = create(:user_legislator_email)

      expect {
        UserLegislatorEmail.create!(
          user_legislator: existing.user_legislator,
          bill: existing.bill
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
