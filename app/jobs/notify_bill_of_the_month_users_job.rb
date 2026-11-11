# frozen_string_literal: true

# @lat: [[bill-of-the-month-notify-job-per-locale-fix#Web push vs native push fan-out]]
class NotifyBillOfTheMonthUsersJob < ApplicationJob
  queue_as :background

  def perform
    # @lat: [[bill-of-the-month-notify-job-per-locale-fix#Why the featured bill notify job iterates per locale]]
    Bill
      .where(scheduled_release_date_utc: Time.zone.today)
      .where.missing(:bill_notification)
      .select(&:notifyable?)
      .each do |bill|
        BillNotification.create!(bill: bill)
        fan_out_native_push(bill)
      rescue => e
        SwayLogging.log_exception(
          "botm_notify.bill_failed",
          exception: e,
          bill_id: bill.id,
          sway_locale_id: bill.sway_locale_id
        )
      end
  end

  private

  def fan_out_native_push(bill)
    payload = {
      kind: "botm_announcement",
      title: "New Bill of the Month",
      body: "#{bill.sway_locale.city_name}: #{BillTitle.headline(bill.title)}",
      data: {bill_id: bill.id.to_s, deep_link: "/bills/#{bill.id}"}
    }

    # @lat: [[bill-of-the-month-notify-job-per-locale-fix#Why native push fan-out uses one joined query]]
    UserDevice
      .with_push
      .joins(user: [:notification_preferences, {user_legislators: :legislator}])
      .where(
        user_legislators: {active: true},
        legislators: {sway_locale_id: bill.sway_locale_id},
        notification_preferences: {key: "botm_announcement", enabled: true}
      )
      .distinct
      .each do |device|
        SendNativePushJob.perform_later(device.id, payload)
      end
  end
end
