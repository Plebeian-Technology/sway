# frozen_string_literal: true

class SwayRegistrationJob < ApplicationJob
  queue_as :default

  # @lat: [[registration-dead-ends#Transient failures retry before registration becomes terminal]]
  TRANSIENT_ERRORS = [
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
    Net::OpenTimeout,
    Net::ReadTimeout,
    SwayGeocode::ServiceUnavailableError
  ].freeze

  # @lat: [[registration-dead-ends#Transient failures retry before registration becomes terminal]]
  retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 3) do |job, error|
    user_id = job.arguments.first
    User.find_by(id: user_id)&.then { |u| u.mark_failed! if u.processing? }
    SwayLogging.log_exception(
      "sway_registration_job.retries_exhausted",
      exception: error,
      user_id: user_id
    )
  end

  def perform(user_id, address_id, sway_locale_id, invited_by_id:, enqueued_at_epoch: nil)
    SwayLogging.info(
      "sway_registration_job.start",
      user_id: user_id,
      address_id: address_id,
      sway_locale_id: sway_locale_id,
      invited_by_id: invited_by_id
    )

    queue_latency_ms = enqueued_at_epoch ? ((Time.current.to_f - enqueued_at_epoch) * 1000).round : nil
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    user = User.find(user_id)
    address = Address.find(address_id)
    sway_locale = SwayLocale.find(sway_locale_id)

    SwayRegistrationService.new(
      user,
      address,
      sway_locale,
      invited_by_id: invited_by_id,
      async: false
    ).call

    exec_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    total_latency_ms = (queue_latency_ms || 0) + exec_duration_ms
    user.transient_funnel_metadata = {
      latency_ms: total_latency_ms,
      service_latency_ms: exec_duration_ms,
      queue_latency_ms: queue_latency_ms
    }

    if user.registered?
      user.complete!
    elsif user.processing?
      user.transient_funnel_metadata = (user.transient_funnel_metadata || {}).merge(reason: "no_representatives")
      user.mark_failed!
    end
  rescue => e
    # @lat: [[registration-dead-ends#Transient failures retry before registration becomes terminal]]
    raise if TRANSIENT_ERRORS.any? { |klass| e.is_a?(klass) }

    user&.transient_funnel_metadata = {
      error_class: e.class.name,
      error_message: e.message.truncate(200)
    }
    mark_failed_if_processing(user_id)
    SwayLogging.log_exception(
      "sway_registration_job.failed",
      exception: e,
      user_id: user_id,
      address_id: address_id,
      sway_locale_id: sway_locale_id,
      invited_by_id: invited_by_id
    )
    raise e
  end

  private

  def mark_failed_if_processing(user_id)
    # @lat: [[registration-dead-ends#Transient failures retry before registration becomes terminal]]
    User.find_by(id: user_id)&.then { |u| u.mark_failed! if u.processing? }
  end
end
