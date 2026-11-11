# frozen_string_literal: true

class DeliverReassignmentNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    ReassignmentNotificationDispatchService.new.call(user_id)
  end
end
