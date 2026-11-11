# frozen_string_literal: true

require_relative "../../lib/sway_local_error_dsn"

# @lat: [[live-llm-http-policy-double-gate#What else the allowlist has to cover]]
module LocalErrorCollectorHosts
  # Ruby uses the first, the browser the second. They differ in development.
  DSN_VARIABLES = %w[RUSTRAK_DSN VITE_RUSTRAK_DSN].freeze

  module_function

  # Named `allowed`, not `all`: RSpec declares an `all` matcher on Object.
  def allowed
    DSN_VARIABLES.filter_map { |name| host_of(ENV[name]) }.uniq
  end

  def host_of(dsn)
    return nil unless SwayLocalErrorDsn.local?(dsn)

    URI.parse(dsn.to_s.strip).host
  rescue URI::InvalidURIError
    nil
  end
end
