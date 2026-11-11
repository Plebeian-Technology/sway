# frozen_string_literal: true

# @lat: [[android-app-links#Why an empty list is announced rather than refused]]
if Rails.env.production?
  Rails.application.config.after_initialize do
    next if Sway::Settings.mobile.android_cert_sha256_fingerprints.any?

    SwayLogging.warn(
      "android_app_links.no_fingerprints",
      served_at: "/.well-known/assetlinks.json",
      setting: "ANDROID_CERT_SHA256_FINGERPRINTS",
      message: "the published sha256_cert_fingerprints list is empty, so Android matches no app against it"
    )
  end
end
