class OnDeactivatedPhoneDeleteUserJob < ApplicationJob
  queue_as :background

  def perform(*args)
    if Rails.env.development?
      Rails.logger.info("Testing Job - OnDeactivatedPhoneDeleteUserJob. Found #{User.count} users in dev.")
    else
      account_sid = ENV["TWILIO_ACCOUNT_SID"]
      auth_token = ENV["TWILIO_AUTH_TOKEN"]
      client = Twilio::REST::Client.new(account_sid, auth_token)

      deactivation = client.messaging.v1.deactivations.fetch(date: Time.zone.today)

      response = Faraday.get(deactivation.redirect_to)
      phones = response.body.split("\n").map { |phone| phone.slice(1..) }

      count = 0

      # Batch the queries to User
      phones.in_groups_of(200) do |grouped_phones|
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
end
