# frozen_string_literal: true

require "rails_helper"

RSpec.describe VotingReminderJob, type: :job do
  describe "#perform" do
    let(:sway_locale) { create(:sway_locale) }
    let(:district) { create(:district, sway_locale: sway_locale) }
    let(:legislator) { create(:legislator, district: district) }
    let(:user) do
      # A before_create hook forces both flags to false, so turn them on after.
      u =
        create(:user, is_phone_verified: true, sms_notifications_enabled: true)
      u.update!(sms_notifications_enabled: true, is_phone_verified: true)
      u
    end
    let(:bill) do
      create(
        :bill,
        sway_locale: sway_locale,
        scheduled_release_date_utc: 5.days.ago.to_date
      )
    end

    # @lat: [[voting-reminder-job-locale-query#Why VotingReminderJob finds locale users through user_legislators]]
    before do
      create(:user_legislator, user: user, legislator: legislator, active: true)
    end

    it "selects a user who registered via SwayRegistrationService (active user_legislators only)" do
      expect(SmsNotificationService).to receive(:send_voting_reminder).with(
        user,
        bill
      )

      described_class.new.perform_now

      expect(UserBillReminder.exists?(user: user, bill: bill)).to be true
    end

    it "does not send if user has voted" do
      create(:user_vote, user: user, bill: bill, support: "for")

      expect(SmsNotificationService).not_to receive(:send_voting_reminder)

      described_class.new.perform_now
    end

    it "does not send if already reminded" do
      create(:user_bill_reminder, user: user, bill: bill, sent_at: Time.current)

      expect(SmsNotificationService).not_to receive(:send_voting_reminder)

      described_class.new.perform_now
    end

    it "does not send if user opted out" do
      user.update(sms_notifications_enabled: false)
      expect(SmsNotificationService).not_to receive(:send_voting_reminder)
      described_class.new.perform_now
    end

    it "does not select a user whose only user_legislator in the locale is inactive" do
      inactive_user =
        create(:user, is_phone_verified: true, sms_notifications_enabled: true)
      inactive_user.update!(is_phone_verified: true, sms_notifications_enabled: true)
      create(
        :user_legislator,
        user: inactive_user,
        legislator: legislator,
        active: false
      )

      expect(SmsNotificationService).to receive(:send_voting_reminder).with(
        user,
        bill
      )

      described_class.new.perform_now

      expect(UserBillReminder.exists?(user: inactive_user, bill: bill)).to be false
    end
  end
end
