# typed: true

require 'google/cloud/storage'

# pre-signed urls
# https://cloud.google.com/storage/docs/access-control/signing-urls-with-helpers#client-libraries
# private writes, public reads
# https://cloud.google.com/storage/docs/access-control/making-data-public
module SwayGoogleCloudStorage
  extend ActiveSupport::Concern

  GOOGLE_CLOUD_PROJECT_ID = 'sway-421916'

  BUCKETS = {
    ASSETS: 'sway-assets'
  }

  class << self
    # Expose the bucket to cors requests from the frontend
    # https://cloud.google.com/storage/docs/using-cors#client-libraries
    def configure(bucket_name:)
      # The ID of your GCS bucket
      # bucket_name = "your-unique-bucket-name"

      storage = Google::Cloud.storage(
        GOOGLE_CLOUD_PROJECT_ID,
        File.absolute_path('config/keys/sway-bucket-storage.json')
      )
      bucket = storage.bucket bucket_name

      bucket.cors do |c|
        c.add_rule ['https://localhost:3000', 'https://app.sway.vote'],
                   %w[PUT GET],
                   headers: %w[
                     Content-Type
                     x-goog-resumable
                   ],
                   max_age: 3600
      end

      Rails.logger.info "SwayGoogleCloudStorage.configure - Set CORS policies for bucket #{bucket_name}"
    end
  end

  def generate_get_signed_url_v4(bucket_name:, file_name:)
    # The ID of your GCS bucket
    # bucket_name = "your-unique-bucket-name"

    # The ID of your GCS object
    # file_name = "your-file-name"

    storage = Google::Cloud.storage(
      GOOGLE_CLOUD_PROJECT_ID,
      File.absolute_path('config/keys/sway-bucket-storage.json')
    )
    storage_expiry_time = 5 * 60 # 5 minutes

    storage.signed_url bucket_name, file_name, method: 'GET', expires: storage_expiry_time, version: :v4
  end

  def generate_put_signed_url_v4(bucket_name:, file_name:, content_type:)
    # The ID of your GCS bucket
    # bucket_name = "your-unique-bucket-name"

    # The ID of your GCS object
    # file_name = "your-file-name"

    storage = if Rails.env.production?
                Google::Cloud.storage
              else
                Google::Cloud.storage(
                  GOOGLE_CLOUD_PROJECT_ID,
                  File.absolute_path('config/keys/sway-bucket-storage.json')
                )
              end
    storage_expiry_time = 5 * 60 # 5 minutes

    storage.signed_url(
      bucket_name,
      file_name,
      method: 'PUT',
      expires: storage_expiry_time,
      version: :v4,
      headers: { 'Content-Type' => content_type || 'image/png' }
    )
  end
end
