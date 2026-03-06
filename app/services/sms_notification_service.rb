# frozen_string_literal: true

class SmsNotificationService
  def self.send_bill_of_the_week_notification(bill)
    # Find users who have subscribed to the bill's locale via their districts
    users =
      User
        .joins(user_districts: :district)
        .where(districts: { sway_locale_id: bill.sway_locale_id })
        .where(sms_notifications_enabled: true, is_phone_verified: true)
        .distinct

    message =
      "New Bill of the Week in #{bill.sway_locale.city.titleize}: #{bill.title}. Check it out on Sway!"

    users.find_each do |user|
      SmsDeliveryJob.perform_later(to: user.phone, body: message)
    end
  end

  def self.send_voting_reminder(user, bill)
    message =
      "Reminder: You haven't voted on the Bill of the Week in #{bill.sway_locale.city.titleize}: #{bill.title}. Vote now on Sway!"
    SmsDeliveryJob.perform_later(to: user.phone, body: message)
  end
end
