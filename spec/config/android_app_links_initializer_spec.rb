# frozen_string_literal: true

require "rails_helper"

# @lat: [[android-app-links#Why an empty list is announced rather than refused]]
RSpec.describe "config/initializers/android_app_links.rb" do
  # The after_initialize block runs the moment the file is loaded, because the
  # hook it registers on has already fired by the time a spec runs.
  def load_android_app_links(env)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env))
    load Rails.root.join("config", "initializers", "android_app_links.rb").to_s
  end

  it "warns in production when the list it would publish is empty" do
    expect(SwayLogging).to receive(:warn).with(
      "android_app_links.no_fingerprints",
      hash_including(setting: "ANDROID_CERT_SHA256_FINGERPRINTS")
    )

    with_app_config(:mobile, android_cert_sha256_fingerprints: "") do
      load_android_app_links("production")
    end
  end

  it "says nothing in production once a fingerprint is set" do
    expect(SwayLogging).not_to receive(:warn)

    with_app_config(:mobile, android_cert_sha256_fingerprints: "AA:BB:CC") do
      load_android_app_links("production")
    end
  end

  # A deploy must not fail over an Android app that does not exist yet.
  it "leaves other environments silent, and raises in none of them" do
    expect(SwayLogging).not_to receive(:warn)

    with_app_config(:mobile, android_cert_sha256_fingerprints: "") do
      expect { load_android_app_links("development") }.not_to raise_error
    end
  end
end
