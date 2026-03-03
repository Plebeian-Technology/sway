# frozen_string_literal: true

class BillNotificationJob < ApplicationJob
  queue_as :default

  def perform
    SwayLocale.find_each do |locale|
      bill = Bill.of_the_week(sway_locale: locale)
      BillNotification.create!(bill: bill) if bill&.notifyable?
    end
  end
end
