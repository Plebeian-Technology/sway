# frozen_string_literal: true
# typed: true

class BillNotificationJob < ApplicationJob
  queue_as :default

  def perform
    SwayLocale.find_each do |locale|
      bill = Bill.of_the_week(sway_locale: locale)
      if bill&.notifyable?
        BillNotification.create!(bill: bill)
      end
    end
  end
end
