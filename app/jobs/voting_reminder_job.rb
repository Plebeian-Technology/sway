# frozen_string_literal: true

class VotingReminderJob < ApplicationJob
  queue_as :default

  def perform
    # Find bills released 5 days ago
    target_date = 5.days.ago.to_date
    Rails.logger.info("VotingReminderJob - start - target_date=#{target_date}")

    bills = Bill.where(scheduled_release_date_utc: target_date)
    Rails.logger.info(
      "VotingReminderJob - found #{bills.count} bill(s) for scheduled_release_date_utc=#{target_date}",
    )

    bills.find_each do |bill|
      Rails.logger.info(
        "VotingReminderJob - processing bill id=#{bill.id} title=#{bill.title.inspect} sway_locale_id=#{bill.sway_locale_id}",
      )

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

      users_count = users.count
      if users_count.zero?
        Rails.logger.info(
          "VotingReminderJob - no users to remind for bill id=#{bill.id}",
        )
        next
      end

      Rails.logger.info(
        "VotingReminderJob - reminding #{users_count} user(s) for bill id=#{bill.id}",
      )

      users.find_each do |user|
        SmsNotificationService.send_voting_reminder(user, bill)
        UserBillReminder.create!(user: user, bill: bill, sent_at: Time.current)
        Rails.logger.info(
          "VotingReminderJob - reminded user_id=#{user.id} bill_id=#{bill.id}",
        )
      rescue StandardError => e
        Rails.logger.error(
          "VotingReminderJob - failed to remind user_id=#{user.id} bill_id=#{bill.id} error=#{e.class}: #{e.message}",
        )
        if Rails.env.development? || Rails.env.test?
          Rails.logger.debug(e.backtrace)
        end
      end
    end

    Rails.logger.info(
      "VotingReminderJob - finished for target_date=#{target_date}",
    )
  rescue StandardError => e
    Rails.logger.error(
      "VotingReminderJob - fatal error: #{e.class}: #{e.message}",
    )
    raise
  end
end
