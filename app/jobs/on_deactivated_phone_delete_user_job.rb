class OnDeactivatedPhoneDeleteUserJob < ApplicationJob
  queue_as :background

  def perform(*_args)
    if Rails.env.development?
      Rails.logger.info(
        "Testing Job - OnDeactivatedPhoneDeleteUserJob. Found #{User.count} users in dev.",
      )
    else
      count = 0

      # Batch the queries to User
      deactivated_phones.in_groups_of(200) do |grouped_phones|
        User
          .where(phone: grouped_phones)
          .each do |user|
            Rails.logger.warn(
              "Destroying user #{user.id} because their phone number has been de-activated.",
            )
            if user.destroy
              count += 1
            else
              Rails.logger.error(
                "FAILED to destroy user #{user.id} with de-activated phone number.",
              )
              Sentry.capture_message(
                "Failed to destroy user #{user.id} with de-activated phone number in job - OnDeactivatedPhoneDeleteUserJob.",
              )
            end
          end
      end

      Rails.logger.error(
        "Destroyed #{count} users with de-activated phone numbers.",
      )
    end
  end

  def deactivated_phones
    return @deactivated_phones if @deactivated_phones.present?

    _url = deactivation_url
    @deactivated_phones = []
    if _url.nil?
      @deactivated_phones = []
      return @deactivated_phones
    end

    response = Faraday.get(_url.redirect_to)
    if response.nil?
      @deactivated_phones = []
    else
      @deactivated_phones =
        response.body.split("\n").map { |phone| phone.slice(1..) }
    end
    @deactivated_phones
  end

  def deactivation_url
    begin
      twilio_client.messaging.v1.deactivations.fetch(date: Time.zone.today)
    rescue Twilio::REST::RestError => e
      if e.full_message.include?("no deactivation file available for that date")
        Rails.logger.info("No deactivation file available for today.")
        return nil
      else
        Rails.logger.error(e.full_message)
        Sentry.capture_exception(e)
        return nil
      end
    end
  end

  def twilio_client
    account_sid = ENV["TWILIO_ACCOUNT_SID"]
    auth_token = ENV["TWILIO_AUTH_TOKEN"]
    Twilio::REST::Client.new(account_sid, auth_token)
  end
end
