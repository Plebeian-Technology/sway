# frozen_string_literal: true

class SwayRegistrationJob < ApplicationJob
  queue_as :default

  def perform(user_id, address_id, sway_locale_id, invited_by_id:)
    user = User.find(user_id)
    address = Address.find(address_id)
    sway_locale = SwayLocale.find(sway_locale_id)

    SwayRegistrationService.new(
      user,
      address,
      sway_locale,
      invited_by_id: invited_by_id,
      async: false,
    ).run

    user.complete! if user.processing?
  rescue StandardError => e
    mark_failed_if_processing(user_id)
    Rails.logger.error(
      "SwayRegistrationJob failed for User: #{user_id} - #{e.message}",
    )
    raise e
  end

  private

  def mark_failed_if_processing(user_id)
    user = User.find(user_id)
    user.mark_failed! if user.processing?
  end
end
