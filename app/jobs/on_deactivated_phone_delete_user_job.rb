class OnDeactivatedPhoneDeleteUserJob < ApplicationJob
  queue_as :background

  def perform(*args)
    if Rails.env.development?
      Rails.logger.info("Testing Job - OnDeactivatedPhoneDeleteUserJob. Found #{User.count} users in dev.")
    else
      count = 0

      # Batch the queries to User
      deactivated_phones.in_groups_of(200) do |grouped_phones|
        User.where(phone: grouped_phones).each do |user|
          Rails.logger.warn("Destroying user #{user.id} because their phone number has been de-activated.")
          if user.destroy
            count += 1
          else
            Rails.logger.error("FAILED to destroy user #{user.id} with de-activated phone number.")
            Sentry.capture_message("Failed to destroy user #{user.id} with de-activated phone number in job - OnDeactivatedPhoneDeleteUserJob.")
          end
        end
      end

      Rails.logger.error("Destroyed #{count} users with de-activated phone numbers.")
    end
  end

  def deactivated_phones
    response = Faraday.get(deactivation_url.redirect_to)
    response.body.split("\n").map { |phone| phone.slice(1..) }
  end

  def deactivation_url
    twilio_client.messaging.v1.deactivations.fetch(date: Time.zone.today)
  end

  def twilio_client
    account_sid = ENV["TWILIO_ACCOUNT_SID"]
    auth_token = ENV["TWILIO_AUTH_TOKEN"]
    Twilio::REST::Client.new(account_sid, auth_token)
  end
end
