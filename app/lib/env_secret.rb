# frozen_string_literal: true

# @lat: [[env-secret-blank-value-handling#Why EnvSecret.fetch! raises instead of returning nil]]
# @lat: [[pre-autoload-credential-trimming#APNs (config/initializers/apns.rb)]]
# @lat: [[settings-and-secrets#Credentials]]
module EnvSecret
  def self.read(name)
    ENV[name].to_s.strip.presence
  end

  # @lat: [[env-secret-blank-value-handling#Why EnvSecret.fetch! raises instead of returning nil]]
  def self.fetch!(name)
    read(name) || raise(
      KeyError,
      "#{name} is not set (or is blank) in this process's environment"
    )
  end

  # @lat: [[multiline-credentials-over-kamal#Why multiline credentials travel as Base64]]
  def self.read_base64(name)
    encoded = read(name)
    return nil if encoded.nil?

    encoded.unpack1("m0").to_s.strip.presence
  rescue ArgumentError
    Rails.logger&.error("#{name} is set but is not strict Base64, so it was ignored")
    nil
  end

  def self.open_states_api_key!
    fetch!("OPEN_STATES_API_KEY")
  end

  def self.congress_gov_api_key!
    fetch!("CONGRESS_GOV_API_KEY")
  end

  def self.brave_search_api_key!
    fetch!("BRAVE_SEARCH_API_KEY")
  end
end
