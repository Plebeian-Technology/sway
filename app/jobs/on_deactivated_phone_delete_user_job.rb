# frozen_string_literal: true

class OnDeactivatedPhoneDeleteUserJob < ApplicationJob
  queue_as :background

  def perform(*_args)
    if Rails.env.development?
      SwayLogging.info(
        "Testing Job - OnDeactivatedPhoneDeleteUserJob. Found #{User.count} users in dev."
      )
    else
      count = 0

      # @lat: [[on-deactivated-phone-delete-user-job-design#Why batching uses compact + each_slice, not in_groups_of]]
      deactivated_phones.compact.each_slice(200) do |grouped_phones|
        User
          .where(phone: grouped_phones)
          .each do |user|
            SwayLogging.info("deactivated_phone_sweep.destroying", user_id: user.id)
            user.revoke_all_devices!
            if user.destroy
              count += 1
            else
              SwayLogging.error(
                "deactivated_phone_sweep.destroy_failed",
                user_id: user.id,
                errors: user.errors.full_messages
              )
              # @lat: [[on-deactivated-phone-delete-user-job-design#Why a failed destroy reports to Sentry directly]]
              if Rails.env.production?
                Sentry.capture_message(
                  "Failed to destroy user #{user.id} with de-activated phone number in OnDeactivatedPhoneDeleteUserJob."
                )
              end
            end
          end
      end

      SwayLogging.info("deactivated_phone_sweep.completed", destroyed_count: count)
    end
  end

  def deactivated_phones
    return @deactivated_phones if @deactivated_phones.present?

    url = deactivation_url
    @deactivated_phones = []
    if url.nil?
      @deactivated_phones = []
      return @deactivated_phones
    end

    response = Faraday.get(url.redirect_to)
    # @lat: [[on-deactivated-phone-delete-user-job-design#Why only a real leading "+" is stripped]]
    @deactivated_phones = response.body.split(/\r?\n/).filter_map do |line|
      stripped = line.strip
      next unless /\A\+?\d{10,11}\z/.match?(stripped)

      digits = stripped.normalize_phone
      digits if digits.length == 10
    end
    @deactivated_phones
  end

  def deactivation_url
    twilio_client.messaging.v1.deactivations.fetch(date: Time.zone.today)
  rescue Twilio::REST::RestError => e
    if e.full_message.include?("no deactivation file available for that date")
      SwayLogging.info("No deactivation file available for today.")
    else
      # @lat: [[on-deactivated-phone-delete-user-job-design#Why the "no deactivation file" Twilio error skips PII scrubbing]]
      SwayLogging.log_exception("deactivated_phone.deactivation_url_failed", exception: e)
      Sentry.capture_exception(e) if Rails.env.production?
    end
    nil
  end

  def twilio_client
    Sway::TwilioClient.build
  end
end
