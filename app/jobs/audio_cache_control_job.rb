# frozen_string_literal: true

# @lat: [[sway-google-cloud-storage#What the bucket says about caching audio]]
class AudioCacheControlJob < ApplicationJob
  queue_as :background

  def perform
    result = Sway::AudioCacheControl.new(assets_bucket).call(apply: true)

    SwayLogging.info(
      "[AudioCacheControlJob] complete seen=#{result.examined} " \
      "written=#{result.names.size} already_current=#{result.already_set}"
    )
    result.names.size
  end

  private

  def assets_bucket
    SwayGoogleCloudStorage.storage.bucket(
      SwayGoogleCloudStorage::BUCKETS[:ASSETS],
      skip_lookup: true
    )
  end
end
