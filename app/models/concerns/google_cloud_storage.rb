# typed: true

require 'google/cloud/storage'

# pre-signed urls
# https://cloud.google.com/storage/docs/access-control/signing-urls-with-helpers#client-libraries
# private writes, public reads
# https://cloud.google.com/storage/docs/access-control/making-data-public
module GoogleCloudStorage
  extend ActiveSupport::Concern

  DEFAULT_BUCKET = 'sway-assets'

  included do
    def generate_get_signed_url_v4(file_name:, bucket_name:)
      # The ID of your GCS bucket
      # bucket_name = "your-unique-bucket-name"

      # The ID of your GCS object
      # file_name = "your-file-name"

      storage = Google::Cloud::Storage.new
      storage_expiry_time = 5 * 60 # 5 minutes

      storage.signed_url bucket_name, file_name, method: 'GET', expires: storage_expiry_time, version: :v4
    end

    def generate_put_signed_url_v4(file_name:, content_type:, bucket_name:)
      # The ID of your GCS bucket
      # bucket_name = "your-unique-bucket-name"

      # The ID of your GCS object
      # file_name = "your-file-name"

      storage = Google::Cloud::Storage.new
      storage_expiry_time = 5 * 60 # 5 minutes

      storage.signed_url bucket_name, file_name, method: 'PUT', expires: storage_expiry_time, version: :v4,
                                                 headers: { 'Content-Type' => content_type || 'image/png' }
    end
  end
end
