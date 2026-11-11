# frozen_string_literal: true

class SmsNotificationService
  def self.send_bill_of_the_month_notification(bill)
    # @lat: [[sms-notification-service-design#Why recipient selection resolves through active legislator links]]
    users =
      User
        .joins(user_legislators: :legislator)
        .where(user_legislators: {active: true})
        .where(legislators: {sway_locale_id: bill.sway_locale_id})
        .where(sms_notifications_enabled: true, is_phone_verified: true)
        .distinct

    message =
      "New Bill of the Month in #{bill.sway_locale.city.titleize}: #{BillTitle.headline(bill.title)}. Check it out on Sway!"

    users.find_each do |user|
      SmsDeliveryJob.perform_later(to: user.phone, body: message)
    end
  end

  # @lat: [[bill-title-display#Which outbound messages carry the shortened title#Why the earlier segment measurement did not describe real traffic]]
  def self.send_voting_reminder(user, bill)
    message =
      "Sway: You haven't voted on the featured bill in #{bill.sway_locale.city.titleize}: #{BillTitle.headline(bill.title)}. Vote now!"
    SmsDeliveryJob.perform_later(to: user.phone, body: message)
  end
end
