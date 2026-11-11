require "vcr"
require "support/vcr_credential_filter"

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  config.default_cassette_options = {
    record: (ENV["VCR"].to_s == "record") ? :all : :once,
    match_requests_on: %i[method uri body]
  }

  # @lat: [[vcr-credential-filter-design#Why the spec runs VCR's real before_record hook chain instead of a stand-in]]
  VcrCredentialFilter.apply!(config)

  # @lat: [[vcr-credential-filter-design#Why the Google Maps key filter stays alongside the derived set]]
  config.filter_sensitive_data("<GOOGLE_MAPS_API_KEY>") do |interaction|
    interaction.request.uri[/AIza[A-Za-z0-9_-]{35}/]
  end

  config.ignore_localhost = true
  config.allow_http_connections_when_no_cassette = false
end

# @lat: [[live-llm-http-policy-double-gate#Both halves are required — neither is enough alone]]
LiveLlmGate.apply_http_policy!
