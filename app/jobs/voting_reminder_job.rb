# frozen_string_literal: true

class VotingReminderJob < ApplicationJob
  queue_as :default

  def perform
    target_date = 5.days.ago.to_date
    SwayLogging.info("VotingReminderJob - start - target_date=#{target_date}")

    bills = Bill.where(scheduled_release_date_utc: target_date)
    SwayLogging.info(
      "VotingReminderJob - found #{bills.count} bill(s) for scheduled_release_date_utc=#{target_date}"
    )

    bills.find_each do |bill|
      SwayLogging.info(
        "VotingReminderJob - processing bill id=#{bill.id} title=#{bill.title.inspect} sway_locale_id=#{bill.sway_locale_id}"
      )

      voted_user_ids = UserVote.where(bill: bill).select(:user_id)
      reminded_user_ids = UserBillReminder.where(bill: bill).select(:user_id)

      # @lat: [[voting-reminder-job-locale-query#Why VotingReminderJob finds locale users through user_legislators]]
      users =
        User
          .joins(user_legislators: :legislator)
          .where(user_legislators: {active: true})
          .where(legislators: {sway_locale_id: bill.sway_locale_id})
          .where(sms_notifications_enabled: true, is_phone_verified: true)
          .where.not(id: voted_user_ids)
          .where.not(id: reminded_user_ids)
          .distinct

      users_count = users.count
      if users_count.zero?
        SwayLogging.info(
          "VotingReminderJob - no users to remind for bill id=#{bill.id}"
        )
        next
      end

      SwayLogging.info(
        "VotingReminderJob - reminding #{users_count} user(s) for bill id=#{bill.id}"
      )

      users.find_each do |user|
        SmsNotificationService.send_voting_reminder(user, bill)
        UserBillReminder.create!(user: user, bill: bill, sent_at: Time.current)
        SwayLogging.info(
          "VotingReminderJob - reminded user_id=#{user.id} bill_id=#{bill.id}"
        )
      rescue => e
        # @lat: [[twilio-error-phone-redaction#Why VotingReminderJob's inner rescue logs only structured fields and the error class]]
        SwayLogging.error(
          "voting_reminder.remind_failed",
          user_id: user.id,
          bill_id: bill.id,
          error_class: e.class.name
        )
        if Rails.env.local?
          SwayLogging.debug((e.backtrace || []).join("\n"))
        end
      end
    end

    SwayLogging.info(
      "VotingReminderJob - finished for target_date=#{target_date}"
    )
  rescue => e
    # @lat: [[twilio-error-phone-redaction#Why VotingReminderJob's inner rescue logs only structured fields and the error class]]
    SwayLogging.log_exception("voting_reminder.fatal", exception: e)
    raise
  end
end
