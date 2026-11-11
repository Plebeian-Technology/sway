# frozen_string_literal: true

# @lat: [[deploy-values-boot-check#Why a missing bucket name has to stop the deploy]]
Rails.application.config.after_initialize do
  next unless Rails.env.production?

  SwayDeployConfig.require_values!(
    "SWAY_GCP_PROJECT_ID",
    "SWAY_GCS_BUCKET_DB",
    "SWAY_GCS_BUCKET_ASSETS",
    "SWAY_GCS_BUCKET_LEGISLATION",
    "SWAY_LITESTREAM_PATH"
  )
end
