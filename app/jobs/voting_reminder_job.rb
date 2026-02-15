# frozen_string_literal: true
# typed: true

class VotingReminderJob < ApplicationJob
  queue_as :default

  def perform
    # Find bills released 5 days ago
    target_date = 5.days.ago.to_date
    bills = Bill.where(scheduled_release_date_utc: target_date)

    bills.find_each do |bill|
      voted_user_ids = UserVote.where(bill: bill).select(:user_id)
      reminded_user_ids = UserBillReminder.where(bill: bill).select(:user_id)

      users =
        User
          .joins(user_districts: :district)
          .where(districts: { sway_locale_id: bill.sway_locale_id })
          .where(sms_notifications_enabled: true, is_phone_verified: true)
          .where.not(id: voted_user_ids)
          .where.not(id: reminded_user_ids)
          .distinct

      users.find_each do |user|
        SmsNotificationService.send_voting_reminder(user, bill)
        UserBillReminder.create!(user: user, bill: bill, sent_at: Time.current)
      end
    end
  end
end
