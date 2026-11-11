# frozen_string_literal: true

require_relative "local_error_collector_hosts"

# @lat: [[verification-gates#RSpec runtime contracts]]
module LiveLlmGate
  ENV_FLAG = "RUN_LIVE_LLM_TESTS"

  HOST = "api.anthropic.com"
  OPENROUTER_HOST = "openrouter.ai"
  HOSTS = [HOST, OPENROUTER_HOST].freeze

  TIMEOUT_SECONDS = 15

  def self.enabled?
    ENV[ENV_FLAG] == "1"
  end

  # @lat: [[verification-gates#RSpec runtime contracts]]
  def self.apply_http_policy!
    collector_hosts = LocalErrorCollectorHosts.allowed

    if enabled?
      WebMock.disable_net_connect!(allow_localhost: true, allow: [*HOSTS, *collector_hosts])
      VCR.configure do |config|
        HOSTS.each { |host| config.ignore_hosts host }
        collector_hosts.each { |host| config.ignore_hosts host }
      end
    else
      WebMock.disable_net_connect!(allow_localhost: true, allow: collector_hosts)
      VCR.configure do |config|
        HOSTS.each { |host| config.unignore_hosts host }
        collector_hosts.each { |host| config.ignore_hosts host }
      end
    end
  end
end
