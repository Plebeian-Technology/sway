# frozen_string_literal: true

module RateLimitHelpers
  # @lat: [[identity-and-access#Identity and access#The rate limit store swaps in after boot]]
  def with_rate_limit_enabled(scope)
    attribute = RateLimitConfig::FLAG_FOR.fetch(scope)
    allow(Rails.env).to receive(:production?).and_return(true)

    # Rails 8's rate_limit reads `store:` once, when the class loads, so the
    # store object itself has to allow swapping. Every rate-limited controller
    # (the auth controllers and CspReportsController) points straight at
    # ApplicationController::RATE_LIMIT_STORE.
    memory_store = ActiveSupport::Cache::MemoryStore.new
    ApplicationController::RATE_LIMIT_STORE.backend = memory_store

    with_app_config(:rate_limits, **{attribute => true}) do
      yield
    end
  ensure
    ApplicationController::RATE_LIMIT_STORE.backend = ActiveSupport::Cache::NullStore.new
  end

  # The mirror of with_rate_limit_enabled: turns one scope explicitly OFF
  # with a live counting backend wired in, so "does not throttle" is proven
  # under the conditions a caller who genuinely trips the limit would meet --
  # not merely because the backend was never swapped from the no-op default.
  def with_rate_limit_disabled(scope)
    attribute = RateLimitConfig::FLAG_FOR.fetch(scope)
    allow(Rails.env).to receive(:production?).and_return(true)

    memory_store = ActiveSupport::Cache::MemoryStore.new
    ApplicationController::RATE_LIMIT_STORE.backend = memory_store

    with_app_config(:rate_limits, **{attribute => false}) do
      yield
    end
  ensure
    ApplicationController::RATE_LIMIT_STORE.backend = ActiveSupport::Cache::NullStore.new
  end
end
RSpec.configure do |c|
  c.include RateLimitHelpers, type: :request
  # System specs run Puma in a thread of this same process, so the environment
  # flag, the stand-in for Rails.env, and the swapped RATE_LIMIT_STORE backend
  # are all visible to the server.
  c.include RateLimitHelpers, type: :system
end
