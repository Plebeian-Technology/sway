# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_notifications
# Database name: primary
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
  belongs_to :bill

  after_create_commit :notify

  private

  def notify
    SwayLogging.info(
      "BillNotification.notify - sending notifications for bill - #{bill.id} / #{bill.sway_locale.name}"
    )
    SwayPushNotificationService.new(
      title: "New Bill of the Month",
      body: "#{bill.sway_locale.city_name}: #{BillTitle.headline(bill.title)}",
      url: "/bills/#{bill.id}",
      subscriptions: eligible_web_push_subscriptions
    ).send_push_notification

    SmsNotificationService.send_bill_of_the_month_notification(bill)
  rescue Exception => e # rubocop:disable Lint/RescueException
    SwayLogging.log_exception(
      "bill_notification.notify_failed",
      exception: e,
      level: :warn,
      bill_id: bill.id,
      sway_locale_id: bill.sway_locale_id,
      sway_locale_name: bill.sway_locale.name
    )
    Sentry.capture_exception(e) if Rails.env.production?
  end

  def eligible_web_push_subscriptions
    PushNotificationSubscription
      .active
      .joins(user: {user_legislators: :legislator})
      .where(
        user_legislators: {active: true},
        legislators: {sway_locale_id: bill.sway_locale_id}
      )
      .includes(user: :notification_preferences)
      .distinct
      .select { |sub| botm_enabled_for_web_push?(sub.user) }
  end

  def botm_enabled_for_web_push?(user)
    return false if user.nil?

    pref = user.notification_preferences.find { |p| p.key == "botm_announcement" }
    pref.nil? || pref.enabled?
  end
end
