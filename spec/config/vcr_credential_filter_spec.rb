# frozen_string_literal: true

require "rails_helper"
require "support/env_credential_scanner"

# @lat: [[vcr-credential-filter-design#Why a text-scan test, not a behavior test, catches a dead filter]]
RSpec.describe "VCR cassette credential filtering" do
  # @lat: [[vcr-credential-filter-design#Why the spec runs VCR's real before_record hook chain instead of a stand-in]]
  def scrubbed_cassette_text(text)
    interaction = VCR::HTTPInteraction.new(
      VCR::Request.new(
        :get,
        "https://v3.openstates.org/people?apikey=#{text}&api_key=#{text}",
        "posted #{text}",
        {"Authorization" => ["Bearer #{text}"], "X-Api-Key" => [text]}
      ),
      VCR::Response.new(
        VCR::ResponseStatus.new(200, "OK"), {"X-Echo" => [text]}, "body #{text}", "1.1"
      )
    )

    VCR.configuration.invoke_hook(
      :before_record, interaction.hook_aware, instance_double(VCR::Cassette, tags: [])
    )

    [
      interaction.request.uri,
      interaction.request.body,
      interaction.request.headers,
      interaction.response.headers,
      interaction.response.body
    ].inspect
  end

  # The main check. It runs over the derived set instead of a list typed out
  # here, so it cannot drift away from the source of truth for provisioning the
  # way the two dead filters did.
  it "scrubs every credential the project provisions" do
    names = EnvCredentialScanner.new.credential_names

    survivors = names.reject do |name|
      value = "FAKE-#{name}-0123456789"
      with_env(name => value) { !scrubbed_cassette_text(value).include?(value) }
    end

    # Joined into one String rather than compared as an Array, so the whole list
    # survives RSpec's diff truncation. A failure message that trails off in
    # "..." leaves the reader to work the answer out again by hand.
    expect(survivors.join("\n")).to eq(""), <<~MESSAGE
      These provisioned credentials would be written to a cassette verbatim:

      #{survivors.join("\n")}

      The filter set is derived from EnvCredentialScanner#credential_names, which
      derives it from .kamal/secrets-common. If one of these is genuinely not a secret,
      say so in EnvCredentialScanner::NON_APP_CREDENTIALS with the reason -- do
      not add a hand-written exception here.
    MESSAGE
  end

  # @lat: [[vcr-credential-filter-design#Why the redaction length floor is 12]]
  it "refuses to redact a value too short to be told apart from ordinary cassette text" do
    with_env("APNS_ENV" => "production") do
      expect(scrubbed_cassette_text("production")).to include("production")
    end
  end

  # The one filter worth keeping from before. It gives a different guarantee
  # than the derived set: it matches on the key's shape, so it redacts a Google
  # key already sitting in a cassette even in a process where the environment
  # variable is unset. Pinned so the rewrite does not quietly drop it.
  it "still redacts a Google Maps key by its shape when the variable is unset" do
    with_env("GOOGLE_MAPS_API_KEY" => nil) do
      key = "AIza#{"B" * 35}"

      expect(scrubbed_cassette_text(key)).not_to include(key)
    end
  end

  # @lat: [[vcr-credential-filter-design#Why a text-scan test, not a behavior test, catches a dead filter]]
  it "names no credential that does not exist" do
    code = Rails.root.join("spec", "support", "vcr.rb")
      .readlines
      .reject { |line| line.strip.start_with?("#") }
      .join

    hand_written = code.scan(/filter_sensitive_data\(\s*"<([A-Z0-9_]+)>"/).flatten
    unprovisioned = hand_written - EnvCredentialScanner.new.credential_names

    expect(unprovisioned).to eq([]), <<~MESSAGE
      spec/support/vcr.rb filters credentials that are not provisioned:

      #{unprovisioned.join("\n")}

      Either they are dead (delete the filter -- the derived set covers every
      live one) or they are real and missing from .kamal/secrets-common, which is a
      deploy bug worth more than a cassette filter.
    MESSAGE
  end
end
