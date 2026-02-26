# typed: strict

# When a Bill becomes the Bill of the Week
# Notify all users via push
class OnBillBecomesBotwNotifyUsersJob < ApplicationJob
  extend T::Sig

  queue_as :background

  sig { void }
  def perform
    Bill.where(scheduled_release_date_utc: Time.zone.today)
        .left_outer_joins(:bill_notification)
        .where(bill_notifications: { id: nil })
        .find_each do |botw|
      break if botw.notifyable? && BillNotification.create!(bill: botw)
    end
  end
end
