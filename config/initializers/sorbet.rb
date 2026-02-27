# https://sorbet.org/docs/runtime

require "sorbet-runtime"

# (1) Register call_validation_error_handler callback.
# This runs every time a method with a sig fails to type check at runtime.
T::Configuration.call_validation_error_handler =
  lambda do |signature, opts|
    if Rails.env.development? || Rails.env.test?
      Rails.logger.error opts[:pretty_message]
    else
      Rails.env.production?
      begin
        Sentry.capture_message(opts[:pretty_message])
      rescue => e
        Rails.logger.error opts[:pretty_message]
      end
    end
  end
