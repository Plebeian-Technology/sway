# frozen_string_literal: true

module RateLimitResponder
  extend ActiveSupport::Concern

  REPEATED_BLOCK_WINDOW = 5.minutes
  REPEATED_BLOCK_THRESHOLD = 5
  SENTRY_ALERT_SAMPLE_RATIO = 10

  private

  def render_rate_limited
    response.set_header("Retry-After", "60")
    report_repeated_rate_limit
    if request.headers["X-Inertia"].present?
      redirect_back_or_to(root_path, alert: "Too many attempts. Please try again shortly.")
    else
      respond_to do |format|
        format.html { redirect_back_or_to(root_path, alert: "Too many attempts. Please try again shortly.") }
        format.json { render_error(code: "rate_limited", message: "Too many attempts. Please try again shortly.", status: :too_many_requests) }
        format.any { head :too_many_requests }
      end
    end
  end

  # @lat: [[rate-limit-kill-switches#Why RateLimits kill switches default to true and validate strictly#Why repeated rate-limit blocks alert fail-open through the cache]]
  def report_repeated_rate_limit
    actor = current_user&.id ? "user:#{current_user.id}" : "ip:#{request.remote_ip}"
    window_bucket = Time.current.to_i / REPEATED_BLOCK_WINDOW.to_i
    counter_key = "rate_limit_blocks:#{actor}:#{window_bucket}"
    count = Rails.cache.increment(counter_key, 1, expires_in: REPEATED_BLOCK_WINDOW).to_i
    return if count < REPEATED_BLOCK_THRESHOLD
    return unless count == REPEATED_BLOCK_THRESHOLD || (count % SENTRY_ALERT_SAMPLE_RATIO).zero?

    SwayLogging.warn(
      "rate_limit.repeated_blocks",
      actor: actor,
      count: count,
      path: request.path,
      method: request.request_method,
      remote_ip: request.remote_ip,
      user_id: current_user&.id
    )
    Sentry.capture_message(
      "Repeated rate limit blocks (#{actor} on #{request.path}): #{count} blocks in #{REPEATED_BLOCK_WINDOW.inspect}",
      level: :warning,
      tags: {
        actor: actor,
        ip: request.remote_ip,
        path: request.path
      },
      extra: {
        actor: actor,
        count: count,
        path: request.path,
        method: request.request_method,
        remote_ip: request.remote_ip,
        user_id: current_user&.id
      }
    )
  rescue => e
    begin
      SwayLogging.log_exception("rate_limit.telemetry_failed", exception: e, level: :warn)
    rescue
      nil
    end
    nil
  end
end
