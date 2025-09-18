# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: bill_notifications
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#
# Indexes
#
#  index_bill_notifications_on_bill_id  (bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
class BillNotification < ApplicationRecord
  extend T::Sig

  belongs_to :bill

  after_create_commit :notify

  sig { returns(Bill) }
  def bill
    T.cast(super, Bill)
  end

  private

  sig { void }
  def notify
    Rails.logger.info(
      "BillNotification.notify - sending notifications for bill - #{bill.id} / #{bill.sway_locale.name}",
    )
    SwayPushNotificationService.new(
      title: "New Bill of the Week",
      body: "#{bill.sway_locale.city_name}: #{bill.title}",
    ).send_push_notification
  rescue Exception => e # rubocop:disable Lint/RescueException
    Rails.logger.warn(
      "BillNotification.notify - ERROR sending notifications for bill - #{bill.id} / #{bill.sway_locale.name}",
    )
    Rails.logger.error(e)
    Sentry.capture_exception(e)
  end
end
